import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {compactResponse} from '../vendor/siwc-local/dist/compact-response.js';
import {compactTaskContext} from '../src/context-compaction.mjs';
import {Vault} from '../src/vault.mjs';
import {JobStore} from '../src/job-store.mjs';
import {WorkState} from '../src/work-state.mjs';

test('native compaction uses the guarded SDK endpoint and preserves its canonical output unchanged',async()=>{
  const canonical=[{type:'compaction',id:'compact-fixture',encrypted_content:'opaque-synthetic-state'},{role:'user',content:'Keep the original identity'}];
  let sent;
  const result=await compactResponse('synthetic-token',{body:{model:'synthetic',input:[{role:'user',content:'Original task'}],instructions:'Preserve task state'}},new AbortController().signal,async(url,options)=>{
    assert.equal(String(url),'https://api.openai.com/v1/responses/compact');assert.equal(options.redirect,'error');
    const headers=new Headers(options.headers);assert.equal(headers.get('authorization'),'Bearer synthetic-token');assert.equal(headers.get('openai-organization'),null);assert.equal(headers.get('cookie'),null);
    sent=JSON.parse(options.body);return new Response(JSON.stringify({id:'fixture',object:'response.compaction',output:canonical}),{headers:{'content-type':'application/json'}});
  });
  assert.deepEqual(Object.keys(sent).sort(),['input','instructions','model']);assert.deepEqual(result.output,canonical);
});

test('coordinator carries canonical compaction items intact and does not run a second summary',async()=>{
  const store=new JobStore(':memory:',new Vault(randomBytes(32)));
  try{
    const job=store.create('phone','native',{body:{model:'synthetic',input:[{role:'user',content:'Original task'}]}}).job;
    const canonical=[{type:'compaction',id:'checkpoint',encrypted_content:'opaque-synthetic-state',extra_field:'keep-me'}];
    const result=await compactTaskContext({job,checkpoint:{input:[{role:'user',content:'x'.repeat(80000)}]},body:job.payload.body,windowBytes:100000,workState:new WorkState(store),signal:new AbortController().signal,
      provider:{compactTurn:async()=>({output:canonical}),streamTurn:async()=>{assert.fail('Native compaction already succeeded');}}});
    assert.equal(result.mode,'provider_native');assert.deepEqual(result.input.slice(0,canonical.length),canonical);assert.ok(result.source.source_id);
  }finally{store.close();}
});

test('unsupported plan compaction falls back without repeating the unsupported route or exposing its body',async()=>{
  const store=new JobStore(':memory:',new Vault(randomBytes(32)));let native=0,summaries=0;
  try{
    const job=store.create('phone','fallback',{body:{model:'synthetic',input:[]}}).job,checkpoint={input:[{role:'user',content:'x'.repeat(80000)}]};
    const provider={compactTurn:async()=>{native++;throw Object.assign(new Error('private upstream body'),{status:403});},streamTurn:async()=>{summaries++;return {output:[{type:'message',content:[{text:JSON.stringify({summary:'Saved factual state',next_steps:['Continue independent work']})}]}]};}};
    const args={job,checkpoint,body:job.payload.body,windowBytes:100000,workState:new WorkState(store),provider,signal:new AbortController().signal};
    const result=await compactTaskContext(args);assert.equal(result.mode,'model_summary');assert.equal(JSON.stringify(result).includes('private upstream body'),false);
    await compactTaskContext(args);assert.equal(native,1);assert.equal(summaries,2);assert.equal(checkpoint.nativeCompactionUnavailable,true);
  }finally{store.close();}
});
