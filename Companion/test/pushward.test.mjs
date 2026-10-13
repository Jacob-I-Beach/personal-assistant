import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {Vault} from '../src/vault.mjs';
import {JobStore} from '../src/job-store.mjs';
import {Pairing} from '../src/pairing.mjs';
import {PushWardBridge,bridgeState,taskLink} from '../src/pushward.mjs';

function fixture(){
  const store=new JobStore(':memory:',new Vault(randomBytes(32))),pairing=new Pairing(store,store.vault);
  const code=pairing.issue({baseURL:'https://example.test',fingerprint:'0'.repeat(64),serverId:'fixture'});
  const owner=pairing.redeem(code.pairing_code,'Fixture').device_id,sent=[];
  let clock=Date.UTC(2026,9,13),hook;
  const bridge=new PushWardBridge(store,{serverID:'fixture',now:()=>clock,request:async(path,options={})=>{
    sent.push({path,...options});if(hook)await hook(path,options);
    if(path==='/auth/me')return {quota_period_month:202610,notifications_used:0,notifications_limit:500,live_activity_updates_used:0,live_activity_updates_limit:250,integration_key:{permissions:{activities:'manage',notifications:'send'}}};
    return {state:'ongoing',delivery:'all'};
  }});
  const key='hlk_'+'a'.repeat(32),chat=randomUUID();
  const job=store.create(owner,randomUUID(),{conversation_id:chat,profile_id:'fixture',body:{model:'synthetic',input:[]}}).job;
  return {store,pairing,owner,sent,bridge,key,job,chat,tick:n=>{clock+=n;},hook:value=>{hook=value;}};
}

test('bridge uses real task state, private status phrases, correct links and persistent alert deduplication',async()=>{
  const f=fixture();try{
    await f.bridge.configure({key:f.key,owner:f.owner});
    f.store.status(f.job.id,'running','Private prompt must not leave');
    f.bridge.queue(f.job.id,{type:'activity',title:'Private topic alpha'});await f.bridge.deliver(f.job.id);
    const start=f.sent.find(x=>x.method==='PATCH');
    assert.equal(start.body.content.state,'Working on your request');assert.equal(start.body.content.progress,null);
    assert.match(start.body.content.tap_action.url,new RegExp(f.chat));assert.match(start.body.content.tap_action.url,new RegExp(f.job.id));
    f.store.status(f.job.id,'waiting_for_phone','Private question');
    f.bridge.queue(f.job.id,{type:'phone_request',call:{id:'question1',name:'request_input',arguments:{question:'Private question'}}});await f.bridge.deliver(f.job.id);
    f.bridge.queue(f.job.id,{type:'status',status:'waiting_for_phone'});await f.bridge.deliver(f.job.id);
    assert.equal(f.sent.filter(x=>x.path==='/notifications').length,1);
    f.store.status(f.job.id,'completed','Ready');f.bridge.queue(f.job.id,{type:'status',status:'completed'});await f.bridge.deliver(f.job.id);
    const ready=f.sent.filter(x=>x.method==='PATCH').at(-1);
    assert.equal(ready.body.content.icon,'checkmark.circle.fill');assert.equal(ready.body.state,'ongoing');
    assert.equal(f.sent.filter(x=>x.path==='/notifications').length,2);
    assert.equal(JSON.stringify(f.sent).includes('Private question'),false);
    assert.equal(JSON.stringify(f.bridge.status()).includes(f.key),false);
    assert.equal(Buffer.from(f.store.db.prepare('SELECT data FROM pushward_settings').get().data).includes(Buffer.from(f.key)),false);
    await f.bridge.viewed(f.owner,f.job.id);await f.bridge.deliver(f.job.id);
    assert.equal(f.sent.filter(x=>x.method==='PATCH').at(-1).body.state,'ended');
  }finally{await f.bridge.close();f.store.close();}
});

test('an Island delivery error does not suppress attention alerts or change the task outcome',async()=>{
  const f=fixture();try{
    await f.bridge.configure({key:f.key,owner:f.owner});
    f.hook((path,options)=>{if(options.method==='PATCH')throw Object.assign(new Error('Activity rejected'),{status:429});});
    f.store.status(f.job.id,'completed','Ready');f.bridge.queue(f.job.id,{type:'status'});await f.bridge.deliver(f.job.id);
    assert.equal(f.sent.filter(x=>x.path==='/notifications').length,1);
    assert.equal(f.store.get(f.job.id,f.owner).status,'completed');
    await f.bridge.deliver(f.job.id);assert.equal(f.sent.filter(x=>x.path==='/notifications').length,1);
  }finally{await f.bridge.close();f.store.close();}
});

test('a newer completion survives a phase update in flight and routine updates conserve quota',async()=>{
  const f=fixture();try{
    await f.bridge.configure({key:f.key,owner:f.owner});f.store.status(f.job.id,'running','Working');
    let changed=false;
    f.hook((path,options)=>{if(options.method==='PATCH'&&!changed){changed=true;f.store.status(f.job.id,'completed','Ready');f.bridge.queue(f.job.id,{type:'status',status:'completed'});}});
    f.bridge.queue(f.job.id,{type:'web_activity'});await f.bridge.deliver(f.job.id);
    assert.equal(f.bridge.record(f.job.id).state.phase,'ready');
    await f.bridge.deliver(f.job.id);assert.equal(f.sent.filter(x=>x.method==='PATCH').at(-1).body.content.state,'Your reply is ready');
    const c=f.bridge.config();c.quota.activitiesUsed=250;f.bridge.saveConfig(c);
    const next=f.store.create(f.owner,'next',{conversation_id:randomUUID(),body:{model:'synthetic',input:[]}}).job;
    f.store.status(next.id,'completed','Ready');f.bridge.queue(next.id,{type:'status'});const before=f.sent.length;await f.bridge.deliver(next.id);
    assert.equal(f.sent.slice(before).filter(x=>x.method==='PATCH').length,0);assert.equal(f.sent.slice(before).filter(x=>x.path==='/notifications').length,1);
    f.pairing.revoke(f.owner);assert.equal(f.bridge.enabled(f.owner),false);
  }finally{await f.bridge.close();f.store.close();}
});

test('scheduled jobs and explicit notification preference use the same delivery path',async()=>{
  const f=fixture();try{
    await f.bridge.configure({key:f.key,owner:f.owner});
    const job=f.store.create(f.owner,'schedule:fixture',{schedule_id:'schedule',conversation_id:randomUUID(),presentation:{notifications:false},body:{model:'synthetic',input:[]}}).job;
    f.store.status(job.id,'completed','Ready');f.bridge.queue(job.id,{type:'status'});await f.bridge.deliver(job.id);
    assert.equal(f.sent.filter(x=>x.path==='/notifications').length,0);
    assert.match(taskLink(job,'fixture'),/job=/);
    assert.equal(bridgeState({status:'completed'},{type:'web_activity'}).phase,'ready');
  }finally{await f.bridge.close();f.store.close();}
});
