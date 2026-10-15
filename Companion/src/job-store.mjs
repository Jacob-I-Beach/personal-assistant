import { DatabaseSync } from 'node:sqlite';
import { createHash, randomUUID } from 'node:crypto';

export function stableJSON(value) {
  if (Array.isArray(value)) return '[' + value.map(stableJSON).join(',') + ']';
  if (value && typeof value === 'object') return '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + stableJSON(value[key])).join(',') + '}';
  return JSON.stringify(value);
}
export const digest = value => createHash('sha256').update(value).digest('hex');

export class JobStore {
  constructor(path, vault) {
    this.vault = vault;
    this.db = new DatabaseSync(path);
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
      CREATE TABLE IF NOT EXISTS jobs (
        id TEXT PRIMARY KEY, owner TEXT NOT NULL, request_key TEXT NOT NULL,
        request_hash TEXT NOT NULL, status TEXT NOT NULL, created INTEGER NOT NULL,
        updated INTEGER NOT NULL, cursor INTEGER NOT NULL DEFAULT 0, data BLOB NOT NULL,
        checkpoint BLOB, UNIQUE(owner, request_key));
      CREATE TABLE IF NOT EXISTS events (
        job_id TEXT NOT NULL REFERENCES jobs(id), seq INTEGER NOT NULL, data BLOB NOT NULL,
        PRIMARY KEY(job_id, seq));
      CREATE TABLE IF NOT EXISTS operations (
        job_id TEXT NOT NULL REFERENCES jobs(id), id TEXT NOT NULL, request_hash TEXT NOT NULL,
        status TEXT NOT NULL, request BLOB NOT NULL, result BLOB,
        PRIMARY KEY(job_id,id));
      CREATE TABLE IF NOT EXISTS files (
        job_id TEXT NOT NULL REFERENCES jobs(id), id TEXT NOT NULL, version INTEGER NOT NULL,
        sha TEXT NOT NULL, metadata BLOB NOT NULL, data BLOB NOT NULL,
        PRIMARY KEY(job_id,id,version));
      CREATE TABLE IF NOT EXISTS schedules (
        id TEXT PRIMARY KEY, owner TEXT NOT NULL, enabled INTEGER NOT NULL,
        next_run INTEGER, data BLOB NOT NULL);
      CREATE TABLE IF NOT EXISTS cancelled_requests(owner TEXT NOT NULL,request_key TEXT NOT NULL,PRIMARY KEY(owner,request_key));
    `);
    if(!this.db.prepare('PRAGMA table_info(jobs)').all().some(column=>column.name==='summary'))this.db.exec('ALTER TABLE jobs ADD COLUMN summary BLOB');
  }
  create(owner, requestKey, payload) {
    if (typeof requestKey !== 'string' || !requestKey || requestKey.length > 200) throw new Error('A stable request identifier is required.');
    const hash = digest(stableJSON(payload));
    const existing = this.db.prepare('SELECT * FROM jobs WHERE owner=? AND request_key=?').get(owner, requestKey);
    if (existing) {
      if (existing.request_hash !== hash) throw Object.assign(new Error('This request identifier already belongs to different work.'), {status: 409});
      return {job: this.decode(existing), created: false};
    }
    const id = randomUUID(), now = Date.now();
    const cancelled=!!this.db.prepare('SELECT 1 FROM cancelled_requests WHERE owner=? AND request_key=?').get(owner,requestKey);
    this.transaction(()=>{
    this.db.prepare('INSERT INTO jobs(id,owner,request_key,request_hash,status,created,updated,data) VALUES(?,?,?,?,?,?,?,?)')
      .run(id, owner, requestKey, hash, cancelled?'cancelled':'queued', now, now, this.vault.sealJSON(payload, 'job:' + id));
    this.db.prepare('UPDATE jobs SET summary=? WHERE id=?').run(this.vault.sealJSON({title:payload.title??'Assistant task',body:{model:payload.body?.model??payload.model??''},execution_only:payload.execution_only===true},'summary:'+id),id);
    this.appendWithin(id,{type:'status',status:cancelled?'cancelled':'queued',text:cancelled?'Stopped by the user before starting.':'Waiting to start on your computer'});
    });
    return {job: this.get(id, owner), created: true};
  }
  decode(row) {
    if (!row) return null;
    return {id: row.id, owner: row.owner, requestKey: row.request_key, status: row.status,
      createdAt: row.created, updatedAt: row.updated, cursor: row.cursor,
      payload: this.vault.openJSON(row.data, 'job:' + row.id),
      checkpoint: row.checkpoint ? this.vault.openJSON(row.checkpoint, 'checkpoint:' + row.id) : null};
  }
  get(id, owner) {
    const row = this.db.prepare('SELECT * FROM jobs WHERE id=? AND owner=?').get(id, owner);
    if (!row) throw Object.assign(new Error('This task is not available to this device.'), {status: 404});
    return this.decode(row);
  }
  find(owner, requestKey) {
    return this.decode(this.db.prepare('SELECT * FROM jobs WHERE owner=? AND request_key=?').get(owner, requestKey));
  }
  cancelRequest(owner,requestKey){
    if(typeof requestKey!=='string'||!requestKey||requestKey.length>200)throw new Error('Invalid request key.');
    this.db.prepare('INSERT OR IGNORE INTO cancelled_requests(owner,request_key) VALUES(?,?)').run(owner,requestKey);
    return this.find(owner,requestKey);
  }
  list(owner) {
    const columns='id,owner,request_key,status,created,updated,cursor,summary';
    const rows = owner ? this.db.prepare('SELECT '+columns+' FROM jobs WHERE owner=? ORDER BY created DESC LIMIT 100').all(owner)
      : this.db.prepare('SELECT '+columns+' FROM jobs ORDER BY created DESC LIMIT 100').all();
    return rows.map(row => this.metadataRow(row));
  }
  assertOwner(id,owner){if(!this.db.prepare('SELECT id FROM jobs WHERE id=? AND owner=?').get(id,owner))throw Object.assign(new Error('This task is not available to this device.'),{status:404});}
  metadata(id,owner){const row=this.db.prepare('SELECT id,owner,request_key,status,created,updated,cursor,summary FROM jobs WHERE id=? AND owner=?').get(id,owner);if(!row)throw Object.assign(new Error('This task is not available to this device.'),{status:404});return this.metadataRow(row);}
  metadataRow(row){
    let payload;
    if(row.summary)payload=this.vault.openJSON(row.summary,'summary:'+row.id);
    else{const old=this.get(row.id,row.owner).payload;payload={title:old.title??'Assistant task',body:{model:old.body?.model??''},execution_only:old.execution_only===true};this.db.prepare('UPDATE jobs SET summary=? WHERE id=?').run(this.vault.sealJSON(payload,'summary:'+row.id),row.id);}
    return {id:row.id,owner:row.owner,requestKey:row.request_key,status:row.status,createdAt:row.created,updatedAt:row.updated,cursor:row.cursor,payload};
  }
  incomplete(owner){return this.db.prepare("SELECT id,owner,request_key,status,created,updated,cursor,summary FROM jobs WHERE status IN ('queued','running','retrying','interrupted','waiting_for_phone','waiting_for_input')"+(owner?' AND owner=?':'')).all(...(owner?[owner]:[])).map(row=>this.metadataRow(row));}
  controlled(id){const row=this.db.prepare('SELECT id,owner,request_key,status,created,updated,cursor,summary FROM jobs WHERE id=?').get(id);if(!row)throw new Error('Task not found.');return this.metadataRow(row);}
  queued(after=0,limit=100){return this.db.prepare("SELECT rowid AS queue_cursor,id,owner,request_key,status,created,updated,cursor,summary FROM jobs WHERE status='queued' AND rowid>? ORDER BY rowid LIMIT ?").all(after,limit).map(row=>({...this.metadataRow(row),queueCursor:row.queue_cursor}));}
  transaction(action){this.db.exec('BEGIN IMMEDIATE');try{const value=action();this.db.exec('COMMIT');return value;}catch(error){this.db.exec('ROLLBACK');throw error;}}
  appendWithin(id,event){
    const row=this.db.prepare('SELECT cursor FROM jobs WHERE id=?').get(id);if(!row)throw new Error('The task no longer exists.');
    const seq=row.cursor+1,value={...event,seq,recordedAt:new Date().toISOString()};
    this.db.prepare('INSERT INTO events(job_id,seq,data) VALUES(?,?,?)').run(id,seq,this.vault.sealJSON(value,`event:${id}:${seq}`));
    this.db.prepare('UPDATE jobs SET cursor=?,updated=? WHERE id=?').run(seq,Date.now(),id);return value;
  }
  checkpointEvents(id,checkpoint,events,before=()=>{}){return this.transaction(()=>{before();this.checkpoint(id,checkpoint);return events.map(event=>this.appendWithin(id,event));});}
  reviewReceipt(id,operationId,event){return this.transaction(()=>{
    this.db.prepare("UPDATE operations SET status='started' WHERE job_id=? AND id=? AND result IS NULL").run(id,operationId);
    return this.appendWithin(id,event);
  });}
  append(id, event) { return this.transaction(()=>this.appendWithin(id,event)); }

  events(id, owner, after = 0, limit = 200) {
    this.assertOwner(id, owner);
    if (!Number.isSafeInteger(after) || after < 0) throw new Error('Invalid progress cursor.');
    return this.db.prepare('SELECT seq,data FROM events WHERE job_id=? AND seq>? ORDER BY seq LIMIT ?')
      .all(id, after, Math.min(200, Math.max(1, limit))).map(row => this.vault.openJSON(row.data, `event:${id}:${row.seq}`));
  }
  replayEvents(id,owner,after=0){
    this.assertOwner(id,owner);
    if(!Number.isSafeInteger(after)||after<0)throw new Error('Invalid progress cursor.');
    const result=[];let bytes=0;
    for(const row of this.db.prepare('SELECT seq,data FROM events WHERE job_id=? AND seq>? ORDER BY seq LIMIT 5000').iterate(id,after)){
      if(result.length>=200||bytes>=2*1024*1024)break;
      const event=this.vault.openJSON(row.data,`event:${id}:${row.seq}`),prior=result.at(-1);
      const same=event.type==='text_delta'&&prior?.type==='text_delta'&&typeof event.text==='string'&&event.seq===(prior.through_seq??prior.seq)+1&&
        ['phase','item_id','output_index','content_index','round'].every(key=>event[key]===prior[key]);
      bytes+=Buffer.byteLength(JSON.stringify(event));
      if(same){prior.text+=event.text;prior.through_seq=event.seq;}
      else result.push(event);
    }
    return result;
  }
  status(id, status, text, extra = {}) {
    return this.transaction(()=>{
    const allowed = ['queued','running','retrying','waiting_for_phone','waiting_for_input','completed','failed','cancelled','interrupted'];
    if (!allowed.includes(status)) throw new Error('Invalid task status.');
    const current = this.db.prepare('SELECT status FROM jobs WHERE id=?').get(id)?.status;
    if (!current) throw new Error('The task no longer exists.');
    if (['completed','cancelled'].includes(current) && current !== status) throw Object.assign(new Error('A finished task cannot be restarted or relabeled.'), {status: 409});
    this.db.prepare('UPDATE jobs SET status=?,updated=? WHERE id=?').run(status, Date.now(), id);
    return this.appendWithin(id, {...extra, type: 'status', status, text});
    });
  }
  checkpoint(id, value) {
    this.db.prepare('UPDATE jobs SET checkpoint=?,updated=? WHERE id=?').run(this.vault.sealJSON(value, 'checkpoint:' + id), Date.now(), id);
  }
  contextBudget(id,owner,bytes){
    if(!Number.isSafeInteger(bytes)||bytes<4096||bytes>4000000)throw new Error('Choose a supported context allowance.');
    const job=this.get(id,owner);job.payload.limits={...job.payload.limits,context_text_bytes:bytes,context_window_tokens:Math.floor(bytes/3)};
    this.db.prepare('UPDATE jobs SET data=? WHERE id=?').run(this.vault.sealJSON(job.payload,'job:'+id),id);
    if(job.checkpoint){delete job.checkpoint.contextBudget;job.checkpoint.contextRecoveries=0;this.checkpoint(id,job.checkpoint);}
  }
  beginOperation(id, operationId, request, location) {
    const hash = digest(stableJSON(request));
    const existing = this.db.prepare('SELECT * FROM operations WHERE job_id=? AND id=?').get(id, operationId);
    if (existing) {
      if (existing.request_hash !== hash) throw new Error('The operation identifier does not match its original request.');
      return {status: existing.status, result: existing.result ? this.vault.openJSON(existing.result, `result:${id}:${operationId}`) : null};
    }
    this.db.prepare('INSERT INTO operations(job_id,id,request_hash,status,request) VALUES(?,?,?,?,?)')
      .run(id, operationId, hash, location === 'phone' ? 'waiting_for_phone' : 'started', this.vault.sealJSON(request, `operation:${id}:${operationId}`));
    return {status: 'new', result: null};
  }
  operation(id, operationId) {
    const row = this.db.prepare('SELECT * FROM operations WHERE job_id=? AND id=?').get(id, operationId);
    if (!row) throw new Error('The requested operation does not exist.');
    return {id: row.id, status: row.status, request: this.vault.openJSON(row.request, `operation:${id}:${operationId}`),
      result: row.result ? this.vault.openJSON(row.result, `result:${id}:${operationId}`) : null};
  }
  pendingOperations(id) {
    return this.db.prepare("SELECT id FROM operations WHERE job_id=? AND result IS NULL AND status IN ('waiting_for_phone','awaiting_review') ORDER BY rowid").all(id).map(row=>this.operation(id,row.id));
  }
  operationIndex(id,limit=40) {
    return this.db.prepare('SELECT id,status FROM operations WHERE job_id=? ORDER BY rowid DESC LIMIT ?').all(id,limit);
  }
  finishOperation(id, operationId, result) {
    const prior = this.operation(id, operationId);
    if (prior.result) {
      if (stableJSON(prior.result) !== stableJSON(result)) throw Object.assign(new Error('This operation already has a different outcome.'), {status: 409});
      return prior.result;
    }
    this.db.prepare('UPDATE operations SET status=?,result=? WHERE job_id=? AND id=?')
      .run('completed', this.vault.sealJSON(result, `result:${id}:${operationId}`), id, operationId);
    return result;
  }
  saveFile(jobId, metadata, data, expectedVersion = null) {
    const id = metadata.id ?? randomUUID();
    const last = this.db.prepare('SELECT MAX(version) AS version FROM files WHERE job_id=? AND id=?').get(jobId, id).version ?? 0;
    if ((expectedVersion ?? 0) !== last) throw Object.assign(new Error('This output changed. Read its latest version before updating it.'), {status: 409});
    const version = last + 1, sha = digest(data), info = {...metadata, id, version, sha, bytes: data.length};
    this.db.prepare('INSERT INTO files(job_id,id,version,sha,metadata,data) VALUES(?,?,?,?,?,?)')
      .run(jobId, id, version, sha, this.vault.sealJSON(info, `file-info:${jobId}:${id}:${version}`), this.vault.seal(data, `file:${jobId}:${id}:${version}`));
    return info;
  }
  file(jobId, owner, id, version = null) {
    this.assertOwner(jobId, owner);
    const row = version == null ? this.db.prepare('SELECT * FROM files WHERE job_id=? AND id=? ORDER BY version DESC LIMIT 1').get(jobId, id)
      : this.db.prepare('SELECT * FROM files WHERE job_id=? AND id=? AND version=?').get(jobId, id, version);
    if (!row) throw Object.assign(new Error('This file is not part of the task.'), {status: 404});
    return {metadata: this.vault.openJSON(row.metadata, `file-info:${jobId}:${id}:${row.version}`), data: this.vault.open(row.data, `file:${jobId}:${id}:${row.version}`)};
  }
  files(jobId,owner) {
    this.assertOwner(jobId,owner);
    return this.db.prepare('SELECT f.* FROM files f WHERE job_id=? AND version=(SELECT MAX(version) FROM files n WHERE n.job_id=f.job_id AND n.id=f.id)').all(jobId)
      .map(row=>this.vault.openJSON(row.metadata,`file-info:${jobId}:${row.id}:${row.version}`));
  }
  close() { this.db.close(); }
}
