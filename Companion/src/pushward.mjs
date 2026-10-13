import {randomUUID} from 'node:crypto';

const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const terminal=new Set(['completed','failed','cancelled','interrupted']);
const month=now=>new Date(now).toISOString().slice(0,7).replace('-','');
const effectiveName=call=>call?.name==='use_tool'?call.arguments?.name:call?.name;

// Only app-authored status phrases leave the PC. No prompt, answer, filename,
// Health result or arbitrary model text is copied into this delivery channel.
export function bridgeState(job,event={}){
  const status=job.status,name=effectiveName(event.call);
  if(status==='completed')return {phase:'ready',title:'Your reply is ready',icon:'checkmark.circle.fill',color:'green'};
  if(status==='cancelled')return {phase:'stopped',title:'Stopped',icon:'stop.circle',color:'gray'};
  if(['failed','interrupted'].includes(status))return {phase:'attention',title:'Your task needs attention',icon:'exclamationmark.circle',color:'orange'};
  if(status.startsWith('waiting'))return {phase:'waiting',title:name==='request_input'||status==='waiting_for_input'?'Your answer is needed':'Your review is needed',icon:'questionmark.bubble.fill',color:'orange'};
  if(event.type==='web_activity')return {phase:'research',title:'Checking web sources',icon:'globe',color:'purple'};
  if(event.type==='text_delta'&&event.phase!=='commentary')return {phase:'writing',title:'Writing your reply',icon:'text.bubble',color:'purple'};
  const hint=String(event.title??'').toLowerCase();
  if(/chatgpt is busy|retrying/.test(hint))return {phase:'provider_wait',title:'ChatGPT is busy · retrying',icon:'hourglass',color:'orange'};
  if(/python|calculat|data|document/.test(hint))return {phase:'tools',title:'Working with files and data',icon:'doc.text',color:'purple'};
  if(/browser|web|research/.test(hint))return {phase:'research',title:'Checking web sources',icon:'globe',color:'purple'};
  return {phase:'working',title:'Working on your request',icon:'brain',color:'purple'};
}
export function taskLink(job,serverID){
  if(!UUID.test(job.payload.conversation_id??'')||!UUID.test(job.id))return 'personalassistant://notifications';
  return `personalassistant://task/${job.payload.conversation_id}?job=${job.id}&server=${encodeURIComponent(serverID)}`;
}

async function remoteRequest(path,{method='GET',key,body}={}){
  const response=await fetch('https://api.pushward.app'+path,{method,redirect:'error',signal:AbortSignal.timeout(12000),
    headers:{Authorization:'Bearer '+key,...(body?{'Content-Type':method==='PATCH'?'application/merge-patch+json':'application/json'}:{})},
    ...(body?{body:JSON.stringify(body)}:{})});
  const raw=await response.text();
  if(raw.length>128*1024)throw new Error('PushWard returned an oversized response.');
  let value={};try{value=raw?JSON.parse(raw):{};}catch{throw new Error('PushWard returned an unreadable response.');}
  if(!response.ok){
    const message=response.status===429?'PushWard has reached a rate or free-plan allowance.':response.status===401||response.status===403?'Check the PushWard key and its Activities / Notifications permissions.':`PushWard could not accept this update (${response.status}).`;
    throw Object.assign(new Error(message),{status:response.status,code:String(value.code??''),retryAfter:Math.min(3600,Number(response.headers.get('retry-after'))||60)});
  }
  return value;
}

export class PushWardBridge{
  constructor(store,{request=remoteRequest,now=Date.now,serverID='computer',delay=1500}={}){
    this.store=store;this.request=request;this.now=now;this.serverID=serverID;this.delay=delay;
    this.timer=null;this.busy=null;this.stopped=false;
    store.db.exec('CREATE TABLE IF NOT EXISTS pushward_settings(id INTEGER PRIMARY KEY CHECK(id=1),data BLOB NOT NULL);CREATE TABLE IF NOT EXISTS pushward_jobs(id TEXT PRIMARY KEY,owner TEXT NOT NULL,due INTEGER NOT NULL DEFAULT 0,data BLOB NOT NULL);');
  }
  config(){const row=this.store.db.prepare('SELECT data FROM pushward_settings WHERE id=1').get();return row?this.store.vault.openJSON(row.data,'pushward-config'):null;}
  saveConfig(value){this.store.db.prepare('INSERT OR REPLACE INTO pushward_settings(id,data) VALUES(1,?)').run(this.store.vault.sealJSON(value,'pushward-config'));}
  validOwner(owner){return !!this.store.db.prepare('SELECT id FROM devices WHERE id=? AND revoked=0').get(owner);}
  enabled(owner){const config=this.config();return !!config?.enabled&&config.owner===owner&&this.validOwner(owner);}
  status(owner){const c=this.config();if(!c||owner&&c.owner!==owner)return {configured:false,enabled:false};
    return {configured:true,enabled:c.enabled&&this.validOwner(c.owner),owner:c.owner,last_error:c.error??null,quota:c.quota??null,
      detail:'Economy mode: up to four routine phase changes per task; attention and completion take priority. Status-only delivery through PushWard.'};}
  async configure({key,owner}){
    if(!this.validOwner(owner))throw new Error('Choose the paired iPhone that should receive these updates.');
    if(!/^hlk_[A-Za-z0-9]{32}$/.test(key??''))throw new Error('Enter the integration key shown in PushWard Settings.');
    const info=await this.request('/auth/me',{key});
    const permissions=info.integration_key?.permissions;
    if(permissions&&(permissions.activities!=='manage'||!['send','schedule'].includes(permissions.notifications)))throw new Error('This key needs Activities: Manage and Notifications: Send.');
    const restrictions=info.integration_key?.activity_slugs;
    if(restrictions?.length&&!restrictions.includes('pa-*')&&!restrictions.includes('*'))throw new Error('Allow activity slugs pa-* for this integration key.');
    const old=this.config();
    if(old?.enabled&&old.owner!==owner)throw new Error('Disconnect the existing notification bridge before choosing another phone.');
    this.saveConfig({key,owner,enabled:true,revision:randomUUID(),quota:this.quotaFrom(info),checkedAt:this.now(),error:null});
    this.wake();return this.status();
  }
  quotaFrom(info){return {month:String(info.quota_period_month??month(this.now())),activitiesUsed:Math.max(0,Number(info.live_activity_updates_used)||0),activitiesLimit:Math.min(250,Number(info.live_activity_updates_limit)||250),notificationsUsed:Math.max(0,Number(info.notifications_used)||0),notificationsLimit:Math.min(500,Number(info.notifications_limit)||500),resetsAt:typeof info.quota_resets_at==='string'?info.quota_resets_at:null};}
  async refreshQuota(){const c=this.config();if(!c)return this.status();
    const info=await this.request('/auth/me',{key:c.key});
    const latest=this.config();if(latest?.revision===c.revision)this.saveConfig({...latest,quota:this.quotaFrom(info),checkedAt:this.now(),error:null});
    return this.status();
  }
  record(id){const row=this.store.db.prepare('SELECT due,data FROM pushward_jobs WHERE id=?').get(id);return row?{...this.store.vault.openJSON(row.data,'pushward-job:'+id),due:row.due}:null;}
  save(record,due=0){this.store.db.prepare('INSERT INTO pushward_jobs(id,owner,due,data) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET due=excluded.due,data=excluded.data').run(record.id,record.owner,due,this.store.vault.sealJSON(record,'pushward-job:'+record.id));}
  checkpoint(record,due=0){
    const latest=this.record(record.id);
    // Network I/O yields to newer worker events. Keep their desired state while
    // committing receipts from this attempt; never overwrite a newer phase.
    if(latest&&latest.generation!==record.generation){
      this.save({...record,state:latest.state,call:latest.call,generation:latest.generation,revision:latest.revision,viewed:latest.viewed||record.viewed,attempts:0},latest.due||this.now());
    }else this.save(record,due);
  }
  noteError(message){const c=this.config();if(c)this.saveConfig({...c,error:message});}
  reserve(kind,important=false){const c=this.config();if(!c?.enabled)return false;
    const q=c.quota;if(!q||q.month!==month(this.now()))return false;
    const used=kind==='activity'?'activitiesUsed':'notificationsUsed',limit=kind==='activity'?'activitiesLimit':'notificationsLimit';
    const reserve=kind==='activity'&&!important?12:0;
    if(q[used]>=q[limit]-reserve){this.noteError(kind==='activity'?'Live Activity allowance is low or exhausted. Important alerts use the separate notification allowance.':'The free notification allowance is exhausted. Tasks continue and remain in the app.');return false;}
    // Reserve before I/O: an ambiguous network failure may already have counted.
    q[used]++;this.saveConfig({...c,quota:q});return true;
  }
  queue(id,event){
    if(this.stopped||!['status','activity','text_delta','web_activity','phone_request'].includes(event.type))return;
    const meta=this.store.db.prepare('SELECT owner FROM jobs WHERE id=?').get(id);if(!meta||!this.enabled(meta.owner))return;
    const job=this.store.get(id,meta.owner);if(job.payload.execution_only||job.status==='queued')return;
    const state=bridgeState(job,event),prior=this.record(id);
    const call=event.call?.id??(state.phase==='waiting'?prior?.call:null);
    const record={...prior,id,owner:job.owner,slug:'pa-'+id,state,call,revision:this.config().revision,attempts:0,generation:(prior?.generation??0)+1};
    const important=['ready','waiting','attention','stopped'].includes(state.phase);
    if(prior?.viewed&&terminal.has(job.status))return;
    if(prior?.lastPhase===state.phase&&(!important||prior.call===call))return;
    if(prior?.due>0&&prior.state.phase===state.phase&&prior.call===call)return;
    if(!important&&prior?.routineUpdates>=4)return;
    const due=important?this.now():Math.max(this.now()+this.delay,(prior?.lastSentAt??0)+45000);
    this.save(record,due);this.wake();
  }
  wake(){
    if(this.stopped||this.busy)return;
    clearTimeout(this.timer);
    const row=this.store.db.prepare('SELECT MIN(due) AS due FROM pushward_jobs WHERE due>0').get();if(!row?.due)return;
    this.timer=setTimeout(()=>{this.busy=this.drain().finally(()=>{this.busy=null;this.wake();});},Math.max(10,row.due-this.now()));this.timer.unref?.();
  }
  async drain(){
    for(const row of this.store.db.prepare('SELECT id FROM pushward_jobs WHERE due>0 AND due<=? ORDER BY due LIMIT 12').all(this.now())){
      try{await this.deliver(row.id);}catch{this.noteError('PushWard delivery could not be confirmed. The task and its results are still saved.');}
    }
  }
  async deliver(id){
    let record=this.record(id),c=this.config();if(!record)return;
    if(!this.enabled(record.owner)||record.revision!==c.revision){this.save(record);return;}
    const job=this.store.get(id,record.owner);
    if(record.viewed&&!record.created){this.save(record);return;}
    if(terminal.has(job.status)||job.status.startsWith('waiting')&&record.state.phase!=='waiting')record.state=bridgeState(job);
    const important=['ready','waiting','attention','stopped'].includes(record.state.phase);
    try{
      if(!c.quota||c.quota.month!==month(this.now())||this.now()-c.checkedAt>60000){await this.refreshQuota();c=this.config();}
      const link=taskLink(job,this.serverID),s=record.state;
      let activityError=null;
      if(this.reserve('activity',important))try{
        if(!record.created){await this.retireReady(record.owner,record.id,c.key);await this.request('/activities',{method:'POST',key:c.key,body:{slug:record.slug,name:'Personal Assistant',priority:4,ended_ttl:86400,dismissal_ttl:0}});record.created=true;this.checkpoint(record);}
        const ending=record.viewed||s.phase==='stopped';
        const content={template:'generic',state:s.title,subtitle:s.phase==='ready'?'Tap to open the answer':s.phase==='waiting'?'Open your chat to answer or review':'Your task continues on your computer',icon:s.icon,accent_color:s.color,
          tap_action:{url:link},url_action:{url:link,title:s.phase==='waiting'?'Open question':'Open chat',icon:'arrow.up.forward'},progress:null};
        await this.request('/activities/'+record.slug,{method:'PATCH',key:c.key,body:{state:ending?'ended':'ongoing',content,stale_ttl:s.phase==='ready'?7200:28800,dismissal_ttl:0}});
        record.lastPhase=s.phase;record.lastSentAt=this.now();record.routineUpdates=(record.routineUpdates??0)+(important?0:1);record.ended=ending;
        this.checkpoint(record);
      }catch(error){activityError=error;}
      const alertKey=s.phase+':'+(record.call??'');
      if(!record.viewed&&['ready','waiting','attention'].includes(s.phase)&&job.payload.presentation?.notifications!==false&&record.alertAttempt!==alertKey&&this.reserve('notification',true)){
        // Do not retry an ambiguous alert POST: the service may have accepted it.
        record.alertAttempt=alertKey;this.checkpoint(record);
        const response=await this.request('/notifications',{method:'POST',key:c.key,body:{title:s.title,body:s.phase==='ready'?'Open Personal Assistant to see your answer and saved results.':'Open Personal Assistant to answer or review the next step.',url:link,
          source:'personal-assistant',source_display_name:'Personal Assistant',thread_id:job.payload.conversation_id,collapse_id:'pa-'+id,level:'active'}});
        if(response.delivery==='none')throw new Error('PushWard has no reachable notification target.');
      }
      if(activityError)throw activityError;
      this.checkpoint(record);
    }catch(error){
      const latest=this.record(id)??record;latest.attempts=(latest.attempts??0)+1;
      const retry=latest.attempts<3&&![401,403,422].includes(error.status);
      this.save(latest,retry?this.now()+Math.max(60000,(error.retryAfter??60)*1000):0);
      this.noteError(error.status?error.message:'PushWard delivery could not be confirmed. Your task continues; check the connection before retrying alerts.');
    }
  }
  async retireReady(owner,except,key){
    for(const row of this.store.db.prepare('SELECT id FROM pushward_jobs WHERE owner=? AND id<>?').all(owner,except)){
      const old=this.record(row.id);if(!old?.created||old.ended||!['ready','stopped','attention'].includes(old.lastPhase))continue;
      if(!this.reserve('activity',true))return;
      try{await this.request('/activities/'+old.slug,{method:'PATCH',key,body:{state:'ended',dismissal_ttl:0}});this.save({...old,ended:true,viewed:true});}catch{}
    }
  }
  async viewed(owner,id){
    this.store.assertOwner(id,owner);const record=this.record(id);if(!record||record.owner!==owner)return;
    if(!terminal.has(this.store.metadata(id,owner).status))return;
    record.viewed=true;record.generation=(record.generation??0)+1;this.save(record,this.now());this.wake();
  }
  async disconnect(){
    const c=this.config();if(c){
      this.saveConfig({...c,enabled:false,error:null});
      await this.busy;
      for(const row of this.store.db.prepare('SELECT id FROM pushward_jobs WHERE owner=?').all(c.owner)){
        const record=this.record(row.id);if(!record?.created||record.ended)continue;
        try{await this.request('/activities/'+record.slug,{method:'PATCH',key:c.key,body:{state:'ended',dismissal_ttl:0}});this.save({...record,ended:true});}catch{}
      }
      this.saveConfig({...c,enabled:false,key:'',error:null});
    }
    clearTimeout(this.timer);this.store.db.prepare('UPDATE pushward_jobs SET due=0').run();return this.status();
  }
  async test(){
    const c=this.config();if(!c?.enabled)throw new Error('Connect PushWard first.');
    await this.refreshQuota();
    const job=this.store.list(c.owner).filter(j=>!j.payload.execution_only).map(j=>this.store.get(j.id,c.owner)).find(j=>UUID.test(j.payload.conversation_id??''));
    const link=job?taskLink(job,this.serverID):'personalassistant://notifications';
    if(!this.reserve('activity',true)||!this.reserve('notification',true))throw new Error('The free allowance is not available for a test.');
    const slug='pa-connection-test';
    await this.request('/activities',{method:'POST',key:c.key,body:{slug,name:'Personal Assistant',stale_ttl:180,ended_ttl:60,dismissal_ttl:0}});
    await this.request('/activities/'+slug,{method:'PATCH',key:c.key,body:{state:'ongoing',content:{template:'generic',state:'Connection test',subtitle:'Tap to open Personal Assistant',icon:'bubble.left.and.bubble.right.fill',accent_color:'purple',tap_action:{url:link},url_action:{url:link,title:'Open chat'}}}});
    const response=await this.request('/notifications',{method:'POST',key:c.key,body:{title:'Personal Assistant is connected',body:'This is a delivery test. Tap to open your app.',url:link,source:'personal-assistant',thread_id:'personal-assistant-test',collapse_id:'personal-assistant-test',level:'active'}});
    return {requested:true,delivery:response.delivery??'unconfirmed',notice:'Check your iPhone for the Live Activity and alert, then tap to open Personal Assistant.'};
  }
  async close(){this.stopped=true;clearTimeout(this.timer);await this.busy;}
}
