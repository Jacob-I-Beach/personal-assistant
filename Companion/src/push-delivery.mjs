import {connect} from 'node:http2';
import {createPrivateKey,sign} from 'node:crypto';

const terminal=new Set(['completed','failed','cancelled','interrupted']);
const hex=value=>typeof value==='string'&&/^[a-fA-F0-9]{32,1024}$/.test(value);
const appleDate=time=>time/1000-978307200;
export function activityPayload(job,event,previous={}){
  previous??={};
  const now=Date.now(),status=event.status??job.status;
  let phase=status==='completed'?'ready':status.startsWith('waiting')?'waiting':terminal.has(status)?'paused':'working';
  let title=event.title??event.text??previous.title??'Working on your request';
  if(event.type==='text_delta')title='Writing your reply';
  if(event.type==='web_activity')title='Checking web sources';
  if(event.type==='phone_request')title=event.call?.name==='request_input'?'Your answer is needed':'Your iPhone is needed';
  if(status==='completed')title='Your reply is ready';
  const steps=[...(previous.steps??[])];if(phase==='working'&&steps.at(-1)!==title)steps.push(String(title).slice(0,100));
  const state={title:String(title).slice(0,120),detail:phase==='waiting'?'Open your chat to answer or review.':phase==='ready'?'Open the answer and saved results.':'',phase,updatedAt:appleDate(now),steps:steps.slice(-3),onComputer:true};
  if(phase==='ready')state.finishedAt=appleDate(now);
  return {aps:{timestamp:Math.floor(now/1000),event:status==='cancelled'?'end':'update','content-state':state,...(phase==='working'?{'stale-date':Math.floor(now/1000)+180}:{}),...(status==='cancelled'?{'dismissal-date':Math.floor(now/1000)}:{})}};
}

export class PushDelivery {
  constructor(store,{send}={}){
    this.store=store;this.sendOverride=send;this.pending=new Map();this.sending=new Set();this.auth=null;this.lastError=null;this.stopped=false;
    store.db.exec('CREATE TABLE IF NOT EXISTS push_config(id INTEGER PRIMARY KEY CHECK(id=1),data BLOB NOT NULL);CREATE TABLE IF NOT EXISTS push_targets(job_id TEXT PRIMARY KEY,owner TEXT NOT NULL,data BLOB NOT NULL);');
  }
  configuration(){const row=this.store.db.prepare('SELECT data FROM push_config WHERE id=1').get();return row?this.store.vault.openJSON(row.data,'push-config'):null;}
  configure(value){
    if(!/^[A-Z0-9]{10}$/.test(value.team_id??'')||!/^[A-Z0-9]{10}$/.test(value.key_id??'')||!/^[-a-zA-Z0-9.]{3,180}$/.test(value.topic??''))throw new Error('Provide the Apple Team ID, APNs key ID and provisioned app bundle ID.');
    const key=createPrivateKey(value.private_key);if(key.asymmetricKeyType!=='ec'||key.asymmetricKeyDetails?.namedCurve!=='prime256v1')throw new Error('Use the APNs .p8 signing key from Apple.');
    this.store.db.prepare('INSERT OR REPLACE INTO push_config(id,data) VALUES(1,?)').run(this.store.vault.sealJSON({team_id:value.team_id,key_id:value.key_id,topic:value.topic,private_key:value.private_key},'push-config'));this.auth=null;this.lastError=null;
  }
  status(){const config=this.configuration();return {configured:!!config,topic:config?.topic??null,last_error:this.lastError,registered_tasks:this.store.db.prepare('SELECT COUNT(*) AS count FROM push_targets').get().count};}
  target(id){const row=this.store.db.prepare('SELECT owner,data FROM push_targets WHERE job_id=?').get(id);return row?{owner:row.owner,...this.store.vault.openJSON(row.data,'push:'+id)}:null;}
  register(owner,id,value){
    this.store.assertOwner(id,owner);
    if(!['development','production'].includes(value.environment)||!/^[-a-zA-Z0-9.]{3,180}$/.test(value.topic??''))throw new Error('Provide the app push environment and bundle ID.');
    for(const field of ['activity_token','device_token'])if(value[field]!=null&&!hex(value[field]))throw new Error('Invalid push token.');
    const config=this.configuration();if(config&&config.topic!==value.topic)throw new Error('The push key is configured for a different app bundle ID.');
    const previous=this.target(id),record={...previous,...value,owner:undefined,notifications:value.notifications===true,last_state:previous?.last_state??null,last_alert:previous?.last_alert??null};
    this.save(id,owner,record);
    const job=this.store.metadata(id,owner);this.queue(id,{type:'status',status:job.status,text:job.status==='running'?'Working on your request':undefined},true);
    return {registered:true,delivery_configured:!!config};
  }
  save(id,owner,value){this.store.db.prepare('INSERT OR REPLACE INTO push_targets(job_id,owner,data) VALUES(?,?,?)').run(id,owner,this.store.vault.sealJSON(value,'push:'+id));}
  queue(id,event,immediate=false){
    if(this.stopped)return;
    if(!this.configuration()||!this.target(id))return;
    if(!['status','activity','text_delta','web_activity','phone_request'].includes(event.type))return;
    const old=this.pending.get(id);if(old){old.event=event;return;}
    const record={event,timer:null};record.timer=setTimeout(()=>{this.pending.delete(id);this.deliver(id,record.event).catch(()=>{this.lastError='Push delivery needs attention. The task and chat remain saved.';});},immediate||event.type==='status'?20:3000);record.timer.unref?.();this.pending.set(id,record);
  }
  jwt(config){
    if(this.auth&&Date.now()-this.auth.at<40*60*1000)return this.auth.token;
    const head=Buffer.from(JSON.stringify({alg:'ES256',kid:config.key_id})).toString('base64url');
    const body=Buffer.from(JSON.stringify({iss:config.team_id,iat:Math.floor(Date.now()/1000)})).toString('base64url');
    const signature=sign('sha256',Buffer.from(head+'.'+body),{key:config.private_key,dsaEncoding:'ieee-p1363'}).toString('base64url');
    this.auth={at:Date.now(),token:head+'.'+body+'.'+signature};return this.auth.token;
  }
  async send(target,token,type,payload,collapse){
    const config=this.configuration();if(!config)return;
    const headers={':method':'POST',':path':'/3/device/'+token,authorization:'bearer '+this.jwt(config),'apns-topic':config.topic+(type==='liveactivity'?'.push-type.liveactivity':''),'apns-push-type':type,'apns-priority':type==='alert'||payload.aps?.['content-state']?.phase==='ready'?'10':'5','apns-expiration':String(Math.floor(Date.now()/1000)+3600),'apns-collapse-id':collapse};
    if(this.sendOverride)return this.sendOverride({environment:target.environment,headers,payload});
    return new Promise((resolve,reject)=>{
      const session=connect(target.environment==='development'?'https://api.sandbox.push.apple.com':'https://api.push.apple.com');let settled=false;
      const end=error=>{if(settled)return;settled=true;clearTimeout(timer);session.destroy();error?reject(error):resolve();};
      const timer=setTimeout(()=>end(new Error('APNs timed out.')),15000);session.on('error',end);
      const request=session.request(headers);let status=0;request.on('response',h=>{status=Number(h[':status']);});request.on('data',()=>{});request.on('error',end);request.on('end',()=>end(status===200?null:new Error('APNs rejected the update ('+status+').')));request.end(JSON.stringify(payload));
    });
  }
  async deliver(id,event){
    if(this.sending.has(id)){this.queue(id,event);return;}
    const target=this.target(id);if(!target||!this.configuration())return;
    const device=this.store.db.prepare('SELECT revoked FROM devices WHERE id=?').get(target.owner);if(!device||device.revoked)return;
    this.sending.add(id);
    try{
      const job=this.store.get(id,target.owner),payload=activityPayload(job,event,target.last_state);
      if(target.activity_token)await this.send(target,target.activity_token,'liveactivity',payload,'activity-'+id);
      const needsAlert=job.status==='completed'||job.status.startsWith('waiting')||['failed','interrupted'].includes(job.status);
      const alertKey=job.status+':'+(event.call?.id??'');
      const duplicateStatusOnly=!event.call&&target.last_alert?.startsWith(job.status+':');
      if(needsAlert&&target.notifications&&target.device_token&&target.last_alert!==alertKey&&!duplicateStatusOnly){
        const health=job.payload.contains_health_data||job.checkpoint?.containsHealthData;
        const body=health?(job.status==='completed'?'Your reply is ready. Open your chat to see the private results.':'Your task needs your attention. Open the app to review the private details.'):event.call?.name==='review_computer_action'?'A computer action is ready for your review. Open the task to see the exact step.':event.type==='phone_request'?String(event.call?.arguments?.question??'Open your chat to answer or review the next step.').slice(0,180):job.status==='completed'?'Open your chat to see the answer and saved results.':'Your task needs attention. Open the chat to see the next step.';
        await this.send(target,target.device_token,'alert',{aps:{alert:{title:payload.aps['content-state'].title,body},sound:'default','thread-id':job.payload.conversation_id},conversation_id:job.payload.conversation_id,job_id:id},'task-'+id);target.last_alert=alertKey;
      }
      const latest=this.target(id);if(latest)this.save(id,target.owner,{...latest,last_state:payload.aps['content-state'],last_alert:target.last_alert??latest.last_alert});this.lastError=null;
    }finally{this.sending.delete(id);}
  }
  close(){this.stopped=true;for(const record of this.pending.values())clearTimeout(record.timer);this.pending.clear();}
}
