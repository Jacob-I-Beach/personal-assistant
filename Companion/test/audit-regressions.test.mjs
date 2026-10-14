import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes,createHash} from 'node:crypto';
import {mkdtemp,readFile,writeFile,rm,readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve,sep} from 'node:path';
import {Vault} from '../src/vault.mjs';
import {JobStore} from '../src/job-store.mjs';
import {JobRunner} from '../src/job-runner.mjs';
import {Scheduler} from '../src/scheduler.mjs';
import {ToolSessions} from '../src/tool-sessions.mjs';
import {BrowserRuntime} from '../src/browser-runtime.mjs';
import {replaceTextFile} from '../src/file-replacement.mjs';

const schema={type:'object',properties:{},required:[],additionalProperties:false};
const definition=name=>({name,description:'Synthetic tool',parameters:schema});
const final={output:[{type:'message',role:'assistant',content:[{type:'output_text',text:'Completed'}]}]};
const tool=(id,name,args={})=>({type:'function_call',call_id:id,name,arguments:JSON.stringify(args)});
const fixture=t=>{const store=new JobStore(':memory:',new Vault(randomBytes(32)));t.after(()=>store.close());return store;};
const task=(store,key='task',extra={})=>store.create('phone',key,{body:{model:'synthetic',input:[],tools:[]},catalog:[],...extra}).job;
const receipt=call=>({callID:call.id,name:call.name,succeeded:true,output:{status:'saved'}});

test('new task and its first event commit together, including stop-before-send',t=>{
  const store=fixture(t),seal=store.vault.sealJSON.bind(store.vault);
  store.vault.sealJSON=(value,scope)=>{if(value.type==='status')throw new Error('First event could not be stored');return seal(value,scope);};
  assert.throws(()=>task(store,'failed-create'));
  assert.equal(store.find('phone','failed-create'),null);
  store.vault.sealJSON=seal;
  const retry=task(store,'failed-create');assert.equal(store.events(retry.id,'phone').length,1);
  store.cancelRequest('phone','already-stopped');const cancelled=task(store,'already-stopped');
  assert.equal(cancelled.status,'cancelled');assert.equal(store.events(cancelled.id,'phone')[0].status,'cancelled');
});

test('scheduled discovery and dispatch deny private host access including use_tool',async t=>{
  const store=fixture(t),executed=[];let calls=0;
  const runtime={definitions:['computer_desktop','run_computer_command','computer_browser','connect_computer_folder','run_python'].map(definition),supports:()=>true,title:()=>'',execute:async call=>{executed.push(call.name);return receipt(call);}};
  const provider={streamTurn:async({body})=>{
    assert.ok(body.tools.every(item=>item.type==='web_search'||item.name==='run_python'));
    return calls++?final:{output:[tool('d','computer_desktop'),tool('c','use_tool',{name:'run_computer_command',arguments:[]}),tool('b','computer_browser'),tool('p','run_python')]};
  }};
  const runner=new JobRunner(store,provider,runtime),source=task(store,'source',{profile_id:'profile'});
  let now=1_000_000_000_000;const schedules=new Scheduler(store,runner,{now:()=>now});
  schedules.create('phone',{request_key:'schedule',source_job_id:source.id,title:'Research',prompt:'Use public information',run_at:[now+1000]});
  now+=2000;await schedules.tick();await Promise.all([...runner.active.values()].map(item=>item.promise));
  assert.deepEqual(executed,['run_python']);
});

test('receipt replay and consumed checkpoint commit together without repeating effects',async t=>{
  const store=fixture(t);let effects=0,requests=0,failReceipt=true;
  const seal=store.vault.sealJSON.bind(store.vault);
  store.vault.sealJSON=(value,scope)=>{if(value.type==='executed_tool'&&failReceipt){failReceipt=false;throw new Error('Injected receipt failure');}return seal(value,scope);};
  const runtime={definitions:[definition('synthetic_effect')],supports:()=>true,title:()=>'',execute:async call=>{effects++;return receipt(call);}};
  const provider={streamTurn:async()=>requests++?final:{output:[tool('effect','synthetic_effect')]}};
  const runner=new JobRunner(store,provider,runtime),job=task(store);
  await runner.start(job.id,job.owner);
  assert.equal(store.get(job.id,job.owner).checkpoint.pending.length,1);
  assert.equal(store.operation(job.id,'effect').result.succeeded,true);
  await runner.start(job.id,job.owner);
  assert.equal(effects,1);assert.equal(store.get(job.id,job.owner).status,'completed');
  assert.equal(store.events(job.id,job.owner).filter(event=>event.type==='executed_tool').length,1);
});

test('a failed terminal event leaves both previous status and cursor intact',t=>{
  const store=fixture(t),job=task(store),seal=store.vault.sealJSON.bind(store.vault);
  store.vault.sealJSON=(value,scope)=>{if(value.type==='status'&&value.status==='completed')throw new Error('Injected status failure');return seal(value,scope);};
  assert.throws(()=>store.status(job.id,'completed','Ready'));
  const saved=store.get(job.id,job.owner);assert.equal(saved.status,'queued');assert.equal(saved.cursor,job.cursor);
  store.vault.sealJSON=seal;store.status(job.id,'completed','Ready');assert.equal(store.events(job.id,job.owner).at(-1).status,'completed');
});

test('schedule idempotency admission and owner shutdown include older rows',t=>{
  const store=fixture(t),source=task(store),now=1_000_000_000_000;
  const schedules=new Scheduler(store,{active:new Map()},{now:()=>now});
  const args=key=>({request_key:key,source_job_id:source.id,title:key,prompt:'Research',run_at:[now+1000]});
  const old=schedules.create('phone',args('old'));
  for(let index=0;index<105;index++){const item=schedules.create('phone',args('new-'+index));schedules.setEnabled('phone',item.id,false);}
  assert.equal(schedules.create('phone',args('old')).id,old.id);
  assert.equal(schedules.setEnabled('phone',old.id,false).enabled,false);schedules.setEnabled('phone',old.id,true);
  for(let index=0;index<19;index++)schedules.create('phone',args('active-'+index));
  assert.throws(()=>schedules.create('phone',args('too-many')),/existing schedule/);
  schedules.stopOwner('phone');assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM schedules WHERE enabled=1').get().n,0);
});

test('exact control lookup and queued recovery are independent of the display page',t=>{
  const store=fixture(t),old=task(store,'old');
  for(let index=0;index<110;index++)task(store,'new-'+index);
  assert.equal(store.list().some(item=>item.id===old.id),false);
  assert.equal(store.controlled(old.id).owner,'phone');
  const first=store.queued(),second=store.queued(first.at(-1).queueCursor);
  assert.equal(first[0].id,old.id);assert.equal(first.length+second.length,111);
});

test('revocation cancels queued tool work and forbids a later restart',async t=>{
  const store=fixture(t);let allowed=true,observedSignal,finish;
  const runtime={definitions:[definition('synthetic_effect')],execute:async(call,_job,signal)=>{observedSignal=signal;await new Promise(r=>{finish=r;});return receipt(call);}};
  const sessions=new ToolSessions(store,runtime,{mayRun:()=>allowed});
  const job=sessions.create('phone',{request_key:'turn',conversation_id:'chat'});
  sessions.start(job.id,job.owner,{id:'effect',name:'synthetic_effect',arguments:{}});
  assert.ok(store.incomplete('phone').some(item=>item.id===job.id));
  allowed=false;for(const entry of store.incomplete('phone'))sessions.cancel(entry.id,entry.owner);
  assert.equal(observedSignal.aborted,true);
  assert.throws(()=>sessions.start(job.id,job.owner,{id:'another',name:'synthetic_effect',arguments:{}}),/no longer/);
  const waiting=[...sessions.active.values()].map(item=>item.promise);finish();await Promise.all(waiting);
  assert.equal(store.operation(job.id,'effect').result.succeeded,true,'A late actual effect remains recorded.');
  const runner=new JobRunner(store,{},runtime,null,{mayRun:()=>allowed});assert.throws(()=>runner.start(job.id,job.owner),/no longer/);
});

test('cancelling a handoff interrupts the wait and aborts its source while retaining late receipts',async t=>{
  const store=fixture(t);let finish,sourceSignal;
  const runtime={definitions:[definition('synthetic_effect')],execute:async(call,_job,signal)=>{sourceSignal=signal;await new Promise(r=>{finish=r;});return receipt(call);}};
  const sessions=new ToolSessions(store,runtime),source=sessions.create('phone',{request_key:'turn',conversation_id:'chat'});
  sessions.start(source.id,'phone',{id:'effect',name:'synthetic_effect',arguments:{}});
  const target=task(store,'handoff',{source_tool_session_id:source.id,turn_id:'turn',conversation_id:'chat'}),abort=new AbortController();
  const handoff=sessions.prepareHandoff(target,abort.signal);abort.abort(new Error('Stop requested'));
  await assert.rejects(handoff,/Stop requested/);assert.equal(sourceSignal.aborted,true);
  const waiting=[...sessions.active.values()].map(item=>item.promise);finish();await Promise.all(waiting);
  assert.equal(store.operation(source.id,'effect').result.succeeded,true);
});

test('browser review detects a control becoming a password field',async()=>{
  let type='text',filled=0;
  const node={isConnected:true,tagName:'INPUT',getAttribute:name=>name==='type'?type:name==='aria-label'?'Example':null};
  const handle={evaluate:async fn=>fn(node),fill:async()=>{filled++;}};
  const state={observation:'obs',at:Date.now(),handles:[handle],page:{url:()=> 'https://example.test',isClosed:()=>false},browser:{close:async()=>{}}};
  const browser=new BrowserRuntime({store:{},review:async()=>{type='password';}});browser.session=async()=>state;
  await assert.rejects(browser.execute({id:'fill',arguments:{action:'fill',observation_id:'obs',element_id:0,text:'harmless',reason:'Example'}},{id:'job'},new AbortController().signal),/page changed/);
  assert.equal(filled,0);
});

test('browser cancellation during session creation prevents navigation and closes resources',async()=>{
  let launch,navigations=0,closed=0;const abort=new AbortController();
  const state={page:{goto:async()=>{navigations++;},isClosed:()=>false},browser:{close:async()=>{closed++;}}};
  const browser=new BrowserRuntime({store:{},review:async()=>{}});browser.session=()=>new Promise(r=>{launch=r;});
  const executing=browser.execute({arguments:{action:'open',url:'https://example.test'}},{id:'job'},abort.signal);
  abort.abort(new Error('Stop requested'));launch(state);
  await assert.rejects(executing,/Stop requested/);assert.equal(navigations,0);assert.equal(closed,1);
});

test('browser review binds the inherited form destination, not an unused control override',async()=>{
  let clicked=0;const form={action:'https://example.test/approved',method:'post'};
  const node={isConnected:true,tagName:'BUTTON',form,formAction:'https://example.test/',formMethod:'get',getAttribute:name=>name==='aria-label'?'Send':name==='type'?'submit':null};
  const handle={evaluate:async fn=>fn(node),click:async()=>{clicked++;}};
  const state={observation:'obs',at:Date.now(),handles:[handle],page:{url:()=> 'https://example.test',isClosed:()=>false},browser:{close:async()=>{}}};
  const browser=new BrowserRuntime({store:{},review:async(_job,_call,detail)=>{assert.ok(detail.includes(form.action));form.action='https://example.test/changed';}});browser.session=async()=>state;
  await assert.rejects(browser.execute({id:'click',arguments:{action:'click',observation_id:'obs',element_id:0,reason:'Synthetic review'}},{id:'job'},new AbortController().signal),/page changed/);
  assert.equal(clicked,0);
});

test('file replacement detects competing edits and never exposes a partial target',async t=>{
  const root=await mkdtemp(join(tmpdir(),'assistant-audit-'));assert.ok(resolve(root).startsWith(resolve(tmpdir())+sep));
  t.after(()=>rm(root,{recursive:true,force:true}));const path=join(root,'document.txt'),original=Buffer.from('Original'),expectedHash=createHash('sha256').update(original).digest('hex');
  await writeFile(path,original);const signal=new AbortController().signal;
  await assert.rejects(replaceTextFile({path,data:Buffer.from('Assistant'),expectedHash,signal,beforeCommit:()=>writeFile(path,'External edit')}),/Another edit/);
  assert.equal(await readFile(path,'utf8'),'External edit');assert.deepEqual(await readdir(root),['document.txt']);
  await writeFile(path,original);let previous;
  const receipt=await replaceTextFile({path,data:Buffer.from('Complete replacement'),expectedHash,signal,savePrevious:bytes=>{previous=bytes;}});
  assert.equal(await readFile(path,'utf8'),'Complete replacement');assert.equal(previous.toString(),'Original');assert.equal(receipt.bytes,20);
  await assert.rejects(replaceTextFile({path,data:Buffer.from('Stale replacement'),expectedHash,signal}),/file changed/);
});

test('a cancelled queued file writer cannot release another writer lock',async t=>{
  const root=await mkdtemp(join(tmpdir(),'assistant-audit-'));assert.ok(resolve(root).startsWith(resolve(tmpdir())+sep));
  t.after(()=>rm(root,{recursive:true,force:true}));const path=join(root,'document.txt');await writeFile(path,'Original');
  const expectedHash=createHash('sha256').update('Original').digest('hex'),signal=new AbortController().signal;
  let release,entered;const ready=new Promise(r=>{entered=r;});
  const first=replaceTextFile({path,data:Buffer.from('First'),expectedHash,signal,beforeCommit:async()=>{entered();await new Promise(r=>{release=r;});}});
  await ready;
  const abort=new AbortController(),cancelled=replaceTextFile({path,data:Buffer.from('Cancelled'),expectedHash,signal:abort.signal});
  abort.abort(new Error('Stopped'));await assert.rejects(cancelled,/Stopped/);
  let thirdDone=false;const third=replaceTextFile({path,data:Buffer.from('Third'),expectedHash,signal}).then(()=>{thirdDone=true;},error=>{thirdDone=true;assert.match(error.message,/file changed/);});
  await new Promise(r=>setImmediate(r));assert.equal(thirdDone,false);
  release();await first;await third;assert.equal(await readFile(path,'utf8'),'First');
});

test('legacy duplicate schedule keys are reconciled without deleting history',t=>{
  const store=fixture(t),now=Date.now();
  for(const id of ['original','duplicate'])store.db.prepare('INSERT INTO schedules(id,owner,enabled,next_run,data) VALUES(?,?,?,?,?)').run(id,'phone',1,now,store.vault.sealJSON({request_key:'same',title:id,prompt:'Example',runs:[{at:now,status:'scheduled'}]},'schedule:'+id));
  const scheduler=new Scheduler(store,{active:new Map()});
  assert.equal(scheduler.list('phone').length,2);
  assert.equal(store.db.prepare("SELECT enabled FROM schedules WHERE id='original'").get().enabled,1);
  assert.equal(store.db.prepare("SELECT enabled FROM schedules WHERE id='duplicate'").get().enabled,0);
  assert.throws(()=>store.db.prepare("UPDATE schedules SET request_key='same' WHERE id='duplicate'").run(),/UNIQUE/);
});

test('handoff events and host review receipts retain their transactional boundary',t=>{
  const store=fixture(t),job=task(store),call={id:'host',name:'synthetic_effect',arguments:{}};
  store.beginOperation(job.id,call.id,call,'computer');
  store.db.prepare("UPDATE operations SET status='awaiting_review' WHERE job_id=? AND id=?").run(job.id,call.id);
  const seal=store.vault.sealJSON.bind(store.vault);
  store.vault.sealJSON=(value,scope)=>{if(value.type==='executed_tool'&&value.call.id==='second')throw new Error('Injected publication failure');return seal(value,scope);};
  const events=['first','second'].map(id=>({type:'executed_tool',call:{...call,id},result:receipt({...call,id})}));
  assert.throws(()=>store.checkpointEvents(job.id,{input:['ready']},events));
  assert.equal(store.get(job.id,job.owner).checkpoint,null);
  assert.equal(store.events(job.id,job.owner).length,1);
  assert.throws(()=>store.reviewReceipt(job.id,call.id,events[1]));
  assert.equal(store.operation(job.id,call.id).status,'awaiting_review');
  store.vault.sealJSON=seal;store.reviewReceipt(job.id,call.id,events[1]);
  assert.equal(store.operation(job.id,call.id).status,'started');
  assert.equal(store.events(job.id,job.owner).at(-1).call.id,'second');
});
