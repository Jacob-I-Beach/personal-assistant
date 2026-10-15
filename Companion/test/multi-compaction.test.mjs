import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {Vault} from '../src/vault.mjs';
import {JobStore} from '../src/job-store.mjs';
import {JobRunner} from '../src/job-runner.mjs';

for(const native of [true,false])test(`one task survives multiple ${native?'native':'portable'} compactions without replaying completed work`,async()=>{
  const store=new JobStore(':memory:',new Vault(randomBytes(32)));
  let responses=0,summaries=0,effects=0,nativeAttempts=0;
  const provider={
    compactTurn:async()=>{nativeAttempts++;if(!native)throw Object.assign(new Error('Synthetic unsupported route'),{status:403});return {output:[{type:'compaction',encrypted_content:'synthetic-checkpoint-'+nativeAttempts}]};},
    streamTurn:async({body})=>{
      if(body.text?.format?.name==='task_checkpoint'){
        summaries++;return {output:[{type:'message',role:'assistant',content:[{type:'output_text',text:JSON.stringify({summary:'Saved verified operations; continue remaining steps.',next_steps:['Finish the synthetic task']})}]}]};
      }
      if(++responses<=20)return {output:[{type:'function_call',call_id:'step-'+responses,name:'calculate',arguments:'{}'}]};
      return {output:[{type:'message',role:'assistant',content:[{type:'output_text',text:'All twenty steps completed.'}]}]};
    }
  };
  const runtime={definitions:[{name:'calculate',description:'Synthetic test',parameters:{type:'object',properties:{},required:[],additionalProperties:false}}],supports:()=>true,title:()=>'',execute:async call=>{
    effects++;return {callID:call.id,name:call.name,succeeded:true,output:{step:effects,exact_data:('source-'+effects+' ').repeat(5000)}};
  }};
  try{
    const runner=new JobRunner(store,provider,runtime);
    const job=store.create('phone','multi-context',{title:'Complete twenty steps',body:{model:'synthetic',input:[{role:'user',content:'Finish all twenty steps, preserving exact receipts.'}],tools:[]},catalog:[],limits:{context_text_bytes:100000,context_window_tokens:33333}}).job;
    await runner.start(job.id,'phone');
    assert.equal(store.get(job.id,'phone').status,'completed');assert.equal(effects,20);assert.equal(responses,21);
    const compacted=store.events(job.id,'phone').filter(event=>event.type==='context_compacted');
    assert.ok(compacted.length>=3,`Expected multiple compactions, got ${compacted.length}`);
    assert.ok(compacted.every(event=>event.mode===(native?'provider_native':'model_summary')));
    for(let i=1;i<=20;i++)assert.equal(store.operation(job.id,'step-'+i).result.output.exact_data,('source-'+i+' ').repeat(5000));
    const archived=runner.workState.execute({id:'read',name:'read_task_context',arguments:{source_id:compacted[0].source.source_id,offset:0}},job);
    assert.match(archived.output.text,/Finish all twenty steps/);
    assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM operations WHERE job_id=?').get(job.id).n,20);
    if(native)assert.equal(summaries,0);else {assert.equal(nativeAttempts,1);assert.ok(summaries>=3);}
  }finally{store.close();}
});
