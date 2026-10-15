import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {Vault} from '../src/vault.mjs';
import {JobStore} from '../src/job-store.mjs';
import {JobRunner} from '../src/job-runner.mjs';
import {WorkState} from '../src/work-state.mjs';
import {compactTaskContext,compactionReserve} from '../src/context-compaction.mjs';
import {contextWeight} from '../src/working-context.mjs';
import {SkillRuntime} from '../src/skill-runtime.mjs';
import {fileURLToPath} from 'node:url';

const schema={type:'object',properties:{},required:[],additionalProperties:false};
const definition=name=>({name,description:'Synthetic tool',parameters:schema});
const final=text=>({output:[{type:'message',role:'assistant',content:[{type:'output_text',text}]}]});
const call=(id,name,args={})=>({type:'function_call',call_id:id,name,arguments:JSON.stringify(args)});
const fixture=t=>{const store=new JobStore(':memory:',new Vault(randomBytes(32)));t.after(()=>store.close());return store;};
const task=(store,extra={})=>store.create('phone','task',{title:'Complete synthetic work',body:{model:'synthetic',input:[{role:'user',content:'Finish the requested task; keep the existing file identity.'}],tools:[]},catalog:[],...extra}).job;
const receipt=call=>({callID:call.id,name:call.name,succeeded:true,output:{status:'completed'}});
const settle=async runner=>{for(let i=0;i<20;i++){await new Promise(r=>setImmediate(r));await Promise.all([...runner.active.values()].map(item=>item.promise));if(!runner.active.size)return;}throw new Error('Task did not settle');};

test('PC task crosses 30 rounds and 40 actions automatically without losing operation identity',async t=>{
  const store=fixture(t);let rounds=0,effects=0;
  const runtime={definitions:[definition('calculate')],supports:()=>true,title:()=>'',execute:async c=>{effects++;return receipt(c);}};
  const runner=new JobRunner(store,{streamTurn:async()=>++rounds<=65?{output:[call('c'+rounds,'calculate')]}:final('Verified finished')},runtime);
  const job=task(store);await runner.start(job.id,'phone');
  assert.equal(store.get(job.id,'phone').status,'completed');assert.equal(effects,65);assert.ok(store.get(job.id,'phone').checkpoint.cycles>=2);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM operations WHERE job_id=?').get(job.id).n,65);
  assert.equal(store.events(job.id,'phone').some(e=>e.status==='failed'),false);
});

test('a pending question does not block independent tools; later answer resumes the same saved job',async t=>{
  const store=fixture(t);let turns=0,effects=0;
  const runtime={definitions:[definition('calculate')],supports:name=>name==='calculate',title:()=>'',execute:async c=>{effects++;return receipt(c);}};
  const provider={streamTurn:async({body})=>{
    turns++;if(turns===1)return {output:[call('question','request_input',{question:'Choose a label'}),call('independent','calculate')]};
    if(turns===2){assert.ok(JSON.stringify(body.input).includes('pending'));return final('The calculation is ready; I need your label.');}
    assert.ok(JSON.stringify(body.input).includes('Blue'));return final('Completed with Blue.');
  }};
  const runner=new JobRunner(store,provider,runtime),job=task(store,{catalog:[{name:'request_input',description:'Ask'}]});
  await runner.start(job.id,'phone');assert.equal(effects,1);assert.equal(store.get(job.id,'phone').status,'waiting_for_input');
  assert.equal(store.events(job.id,'phone').filter(e=>e.type==='pending_decisions').length,1);
  const answer={succeeded:true,output:{status:'answered',answer:'Blue'}};
  runner.answer(job.id,'phone','question',answer);await settle(runner);
  assert.equal(store.get(job.id,'phone').status,'completed');assert.equal(effects,1);assert.equal(store.list().length,1);
  runner.answer(job.id,'phone','question',answer);await settle(runner);assert.equal(turns,3);
});

test('review queues an exact host action while independent work proceeds, and never executes after Stop',async t=>{
  for(const stop of [false,true]){
    const store=fixture(t);let calls=0,actions=0,independent=0,runner;
    const runtime={definitions:[definition('reviewed'),definition('read')],supports:()=>true,reviewable:()=>true,title:()=>'',execute:async(c,job,signal)=>{
      if(c.name==='read'){independent++;return receipt(c);}
      const review=await runner.reviewComputer(job,c,{title:'Exact action',detail:'Synthetic reviewed action'},signal);
      if(review.output.status==='approved')actions++;
      return {...receipt(c),succeeded:review.output.status==='approved'};
    }};
    runner=new JobRunner(store,{streamTurn:async()=>++calls===1?{output:[call('effect','reviewed'),call('safe','read')]}:final('Independent work complete; review pending.')},runtime);
    const job=task(store);await runner.start(job.id,'phone');assert.equal(independent,1);assert.equal(actions,0);
    if(stop)runner.cancel(job.id,'phone');
    runner.answer(job.id,'phone','effect_review',{succeeded:true,output:{status:'approved'}});await settle(runner);
    assert.equal(actions,stop?0:1);assert.equal(store.get(job.id,'phone').status,stop?'cancelled':'completed');
  }
});

test('saved pending answer is consumed after worker reconstruction without re-executing completed work',async t=>{
  const store=fixture(t);let count=0;
  const runtime={definitions:[],supports:()=>false};
  const first=new JobRunner(store,{streamTurn:async()=>++count===1?{output:[call('q','request_input',{})]}:final('Waiting on a choice')},runtime);
  const job=task(store,{catalog:[{name:'request_input',description:'Question'}]});await first.start(job.id,'phone');
  store.finishOperation(job.id,'q',{succeeded:true,output:{status:'answered',answer:'Resume safely'}});
  const second=new JobRunner(store,{streamTurn:async({body})=>{assert.ok(JSON.stringify(body.input).includes('Resume safely'));return final('Done');}},runtime);
  await second.start(job.id,'phone');assert.equal(store.get(job.id,'phone').status,'completed');
  assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM operations').get().n,1);
});

test('interactive transient outage retries beyond the former limit with backoff and retains one job',async t=>{
  const store=fixture(t),waits=[];let turns=0;
  const runner=new JobRunner(store,{streamTurn:async()=>{if(++turns<=5)throw Object.assign(new Error('temporary'),{code:'server_error',retryable:true,status:503});return final('Recovered');}},{definitions:[]},null,{sleep:async wait=>{waits.push(wait);}});
  const job=task(store);await runner.start(job.id,'phone');assert.equal(store.get(job.id,'phone').status,'completed');
  assert.deepEqual(waits,[5000,15000,30000,60000,120000]);assert.equal(store.list().length,1);
});

test('compaction uses the reserved 30 percent, saves semantic checkpoint and preserves exact retrievable source',async t=>{
  const store=fixture(t),job=task(store),workState=new WorkState(store);
  const input=[...job.payload.body.input,{role:'assistant',type:'message',content:[{type:'output_text',text:'Evidence '.repeat(9000)}]}];
  let calls=0;
  const body={...job.payload.body,instructions:'Original task instructions',tools:[]};
  const provider={streamTurn:async({body})=>{calls++;assert.deepEqual(body.tools,[]);assert.equal(body.text.format.name,'task_checkpoint');return final(JSON.stringify({summary:'File identity preserved. Calculation checked. Need label.',next_steps:['Wait for the label; do not repeat the completed write.']}));}};
  const result=await compactTaskContext({job,checkpoint:{input},body,windowBytes:100000,workState,provider,signal:new AbortController().signal});
  assert.equal(compactionReserve(1000000),300000);assert.equal(calls,1);assert.equal(result.mode,'model_summary');assert.ok(contextWeight(result.input)<70000);
  const read=workState.execute({id:'read',name:'read_task_context',arguments:{source_id:result.source.source_id,offset:0}},job);
  assert.equal(read.output.text,JSON.stringify(input).slice(0,8000));assert.match(JSON.stringify(result.input),/File identity preserved/);
  assert.throws(()=>workState.execute({id:'read',name:'read_task_context',arguments:{source_id:'outside-task',offset:0}},job));
});

test('invalid summary never executes a returned tool or discards the original source',async t=>{
  const store=fixture(t),job=task(store),workState=new WorkState(store),input=[{role:'user',content:'Keep this exact constraint. '+ 'x'.repeat(35000)}];
  const result=await compactTaskContext({job,checkpoint:{input},body:job.payload.body,windowBytes:40000,workState,provider:{streamTurn:async()=>({output:[call('evil','run_computer_command')]})},signal:new AbortController().signal});
  assert.equal(result.mode,'saved_evidence');assert.equal(store.operationIndex(job.id).length,0);assert.ok(result.source.source_id);
});

test('bundled skills are discoverable and read by stable names with version hashes',async()=>{
  const runtime=new SkillRuntime(fileURLToPath(new URL('../skills/',import.meta.url)));
  const all=await runtime.execute({id:'list',name:'list_skills',arguments:{query:''}});assert.equal(all.output.skills.length,5);
  const read=await runtime.execute({id:'read',name:'read_skill',arguments:{name:'documents-and-data'}});assert.match(read.output.instructions,/assistant.publish/);assert.match(read.output.sha256,/^[a-f0-9]{64}$/);
  await assert.rejects(runtime.execute({id:'outside',name:'read_skill',arguments:{name:'../outside'}}),/not in/);
});

test('repeated failures create a concrete question instead of looping or asking for a generic Continue',async t=>{
  const store=fixture(t);let count=0;
  const runtime={definitions:[definition('broken')],supports:()=>true,title:()=>'',execute:async c=>({...receipt(c),succeeded:false,output:{status:'failed',error:'Synthetic failure'}})};
  const runner=new JobRunner(store,{streamTurn:async()=>({output:[call('try'+(++count),'broken')]})},runtime);
  const job=task(store,{catalog:[{name:'request_input',description:'Ask'}]});await runner.start(job.id,'phone');
  assert.equal(count,6);assert.equal(store.get(job.id,'phone').status,'waiting_for_input');
  const question=store.pendingOperations(job.id).find(op=>op.request.name==='request_input');assert.ok(question);
  runner.answer(job.id,'phone',question.id,{succeeded:true,output:{status:'answered',answer:'Stop this task'}});await settle(runner);
  assert.equal(store.get(job.id,'phone').status,'cancelled');assert.equal(count,6);
});

test('an approved action that started without a final receipt is inspected, never re-executed after restart',async t=>{
  const store=fixture(t),job=task(store);let effects=0;
  const original={id:'effect',name:'reviewed',arguments:{}};
  store.beginOperation(job.id,original.id,original,'computer');
  store.beginOperation(job.id,'effect_review',{id:'effect_review',name:'review_computer_action',arguments:{}},'phone');
  store.finishOperation(job.id,'effect_review',{succeeded:true,output:{status:'approved'}});
  store.checkpoint(job.id,{input:job.payload.body.input,round:1,calls:1,pending:[],deferred:[{original,reviewID:'effect_review'}],final:[]});
  const runner=new JobRunner(store,{streamTurn:async({body})=>{assert.match(JSON.stringify(body.input),/outcome_unknown/);return final('The uncertain result needs inspection.');}},{definitions:[definition('reviewed')],supports:()=>true,execute:async()=>{effects++;}});
  await runner.start(job.id,'phone');assert.equal(effects,0);assert.equal(store.operation(job.id,'effect').result.output.status,'outcome_unknown');
});

test('an archived image remains available as its exact pixels after context rollover',t=>{
  const store=fixture(t),job=task(store),workState=new WorkState(store);
  const bytes=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=','base64');
  const source=workState.archive(job.id,[{role:'user',content:[{type:'input_image',image_url:'data:image/png;base64,'+bytes.toString('base64')}]}]);
  assert.deepEqual(source.images,[{message_index:0,image_index:0}]);
  const result=workState.execute({id:'inspect',name:'inspect_context_image',arguments:{source_id:source.source_id,message_index:0,image_index:0}},job);
  assert.deepEqual(store.file(job.id,job.owner,result.output.files[0].id).data,bytes);
});

test('long replay coalesces text without crossing tool boundaries or dropping raw evidence',t=>{
  const store=fixture(t),job=task(store);
  for(let i=0;i<12000;i++)store.append(job.id,{type:'text_delta',text:'x',item_id:'answer',round:0,phase:'final_answer'});
  store.append(job.id,{type:'activity',title:'Verified the calculation'});
  for(let i=0;i<20;i++)store.append(job.id,{type:'text_delta',text:'y',item_id:'answer',round:0,phase:'final_answer'});
  store.status(job.id,'completed','Ready');
  let cursor=0,pages=0,text='',steps=0;
  while(cursor<store.metadata(job.id,job.owner).cursor){
    const events=store.replayEvents(job.id,job.owner,cursor);pages++;assert.ok(events.length<=200);
    for(const event of events){assert.equal(event.seq,cursor+1);cursor=event.through_seq??event.seq;if(event.type==='text_delta')text+=event.text;if(event.type==='activity')steps++;}
  }
  assert.ok(pages<=3);assert.equal(text,'x'.repeat(12000)+'y'.repeat(20));assert.equal(steps,1);
  assert.equal(store.events(job.id,job.owner,1)[0].text,'x','full raw events are still available');
});
