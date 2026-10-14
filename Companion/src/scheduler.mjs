import {randomUUID} from 'node:crypto';

export class Scheduler {
  constructor(store,runner,{mayRun=()=>true,now=()=>Date.now()}={}){
    this.store=store;this.runner=runner;this.mayRun=mayRun;this.now=now;this.busy=false;
    if(!store.db.prepare('PRAGMA table_info(schedules)').all().some(column=>column.name==='request_key')){
      store.transaction(()=>{
        store.db.exec('ALTER TABLE schedules ADD COLUMN request_key TEXT');
        const keys=new Set();
        for(const row of store.db.prepare('SELECT * FROM schedules ORDER BY rowid').all()){
          const value=this.decode(row),key=JSON.stringify([row.owner,value.request_key]);
          if(keys.has(key)){store.db.prepare('UPDATE schedules SET enabled=0,next_run=NULL WHERE id=?').run(row.id);continue;}
          keys.add(key);store.db.prepare('UPDATE schedules SET request_key=? WHERE id=?').run(value.request_key??null,row.id);
        }
      });
    }
    store.db.exec('CREATE UNIQUE INDEX IF NOT EXISTS schedule_request_identity ON schedules(owner,request_key)');
  }
  decode(row){return row?{id:row.id,owner:row.owner,enabled:!!row.enabled,...this.store.vault.openJSON(row.data,'schedule:'+row.id)}:null;}
  list(owner){return this.store.db.prepare('SELECT * FROM schedules WHERE owner=? ORDER BY rowid DESC LIMIT 100').all(owner).map(row=>this.decode(row));}
  save(schedule){const {id,owner,enabled,...data}=schedule;this.store.db.prepare('INSERT INTO schedules(id,owner,enabled,next_run,data,request_key) VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET enabled=excluded.enabled,next_run=excluded.next_run,data=excluded.data,request_key=excluded.request_key').run(id,owner,enabled?1:0,data.runs.find(run=>run.status==='scheduled')?.at??null,this.store.vault.sealJSON(data,'schedule:'+id),data.request_key??null);}
  create(owner,body){
    if(typeof body.request_key!=='string'||body.request_key.length>200||!body.request_key)throw new Error('A schedule needs a stable request key.');
    const existing=this.decode(this.store.db.prepare('SELECT * FROM schedules WHERE owner=? AND request_key=?').get(owner,body.request_key));
    if(existing){if(existing.prompt!==body.prompt||JSON.stringify(existing.runs.map(run=>run.at))!==JSON.stringify(body.run_at))throw Object.assign(new Error('This schedule request changed.'),{status:409});return existing;}
    if(typeof body.prompt!=='string'||!body.prompt.trim()||body.prompt.length>6000||typeof body.title!=='string'||body.title.length>120)throw new Error('Give the scheduled task a short title and request.');
    const times=body.run_at;
    if(!Array.isArray(times)||times.length<1||times.length>30||times.some((time,index)=>!Number.isSafeInteger(time)||time<this.now()-60000||time>this.now()+90*86400000||(index>0&&time-times[index-1]<15*60000)))throw new Error('Choose 1–30 future runs within 90 days, at least 15 minutes apart.');
    const source=this.store.get(body.source_job_id,owner);
    if(this.store.db.prepare('SELECT COUNT(*) AS count FROM schedules WHERE owner=? AND enabled=1').get(owner).count>=20)throw new Error('Pause or finish an existing schedule before adding another.');
    const selected=this.store.files(source.id,owner).filter(file=>file.role==='input');
    const inputFiles=selected.map(file=>({id:file.id,version:file.version,sha:file.sha}));
    const schedule={id:randomUUID(),owner,enabled:true,request_key:body.request_key,title:body.title,prompt:body.prompt,source_job_id:source.id,input_files:inputFiles,contains_health_data:source.payload.contains_health_data===true||selected.some(file=>file.contains_health_data===true),created_at:this.now(),runs:times.map(at=>({at,status:'scheduled',job_id:null}))};
    this.save(schedule);return schedule;
  }
  setEnabled(owner,id,enabled){const value=this.decode(this.store.db.prepare('SELECT * FROM schedules WHERE owner=? AND id=?').get(owner,id));if(!value)throw new Error('Schedule not found.');if(enabled===true&&!value.enabled&&this.store.db.prepare('SELECT COUNT(*) AS count FROM schedules WHERE owner=? AND enabled=1').get(owner).count>=20)throw new Error('Pause another schedule first.');value.enabled=enabled===true;this.save(value);return value;}
  stopOwner(owner){this.store.db.prepare('UPDATE schedules SET enabled=0,next_run=NULL WHERE owner=?').run(owner);}
  async tick(){
    if(this.busy||this.stopped)return;this.busy=true;
    try{
      const schedules=this.store.db.prepare('SELECT * FROM schedules WHERE enabled=1').all().map(row=>this.decode(row));
      for(const schedule of schedules){
        const source=this.store.get(schedule.source_job_id,schedule.owner);
        if(!await this.mayRun(schedule.owner,source.payload.profile_id)||this.stopped)continue;
        for(const run of schedule.runs){
          if(run.job_id){run.status=this.store.get(run.job_id,schedule.owner).status;if(run.status==='interrupted'&&this.runner.active.size<4)this.runner.start(run.job_id,schedule.owner);continue;}
          if(run.status!=='scheduled'||run.at>this.now())continue;
          if(this.now()-run.at>6*3600000){run.status='missed';continue;}
          if(this.runner.active.size>=4)break;
          const turn=randomUUID(),conversation=randomUUID();
          const body=structuredClone(source.payload.body);
          body.input=[{role:'user',content:[{type:'input_text',text:schedule.prompt}]}];
          body.tools=(body.tools??[]).filter(tool=>tool.type==='web_search');
          body.instructions='You are Personal Assistant running a user-approved scheduled task on their computer. Complete the stated research, analysis or draft using the provided computer tools. This unattended run may research public information and create files only. It cannot send messages, change calendars, access new phone data or create another schedule. Source files are the snapshots explicitly attached to the original task, not automatically refreshed. Report the result and evidence concisely. Current time: '+new Date(this.now()).toISOString();
          const key='schedule:'+schedule.id+':'+run.at;
          const existing=this.store.find(schedule.owner,key);
          const job=existing??this.store.create(schedule.owner,key,{request_key:key,conversation_id:conversation,turn_id:turn,profile_id:source.payload.profile_id,title:schedule.title,display_prompt:schedule.prompt,schedule_id:schedule.id,presentation:source.payload.presentation,contains_health_data:schedule.contains_health_data===true||source.payload.contains_health_data===true,body,catalog:[],limits:{maximum_seconds:600,maximum_tool_calls:12}}).job;
          for(const file of (schedule.input_files??[]).filter(file=>!this.store.files(job.id,schedule.owner).some(saved=>saved.id===file.id))){
            const original=this.store.file(source.id,schedule.owner,file.id,file.version);
            if(original.metadata.sha!==file.sha)throw new Error('A scheduled source snapshot no longer matches its recorded version.');
            this.store.saveFile(job.id,{...original.metadata,version:undefined,sha:undefined},original.data);
          }
          run.job_id=job.id;run.status=job.status;this.save(schedule);
          if(['queued','interrupted'].includes(job.status))this.runner.start(job.id,schedule.owner);
        }
        if(schedule.runs.every(run=>!['scheduled','queued','running','waiting_for_phone','waiting_for_input','interrupted'].includes(run.status)))schedule.enabled=false;
        this.save(schedule);
      }
    }finally{this.busy=false;}
  }
}
