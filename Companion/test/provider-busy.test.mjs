import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {Vault} from '../src/vault.mjs';
import {JobStore} from '../src/job-store.mjs';
import {JobRunner} from '../src/job-runner.mjs';
import {apiError} from '../vendor/siwc-local/dist/errors.js';

test('provider overload retries the same request before any tool effects, then completes',async()=>{
  const store=new JobStore(':memory:',new Vault(randomBytes(32)));let attempts=0;const waits=[];
  const provider={streamTurn:async()=>{if(++attempts<3)throw Object.assign(new Error('Provider overloaded'),{code:'server_is_overloaded',status:200});return {output:[{type:'message',role:'assistant',content:[{type:'output_text',text:'Ready'}]}]};}};
  const runner=new JobRunner(store,provider,{definitions:[]},undefined,{sleep:async n=>waits.push(n)});
  try{const job=store.create('phone','same-request',{body:{model:'synthetic',input:[]},catalog:[]}).job;
    await runner.start(job.id,'phone');assert.equal(store.get(job.id,'phone').status,'completed');
    assert.deepEqual(waits,[5000,15000]);assert.equal(store.list('phone').length,1);
    assert.equal(store.events(job.id,'phone').filter(e=>e.type==='executed_tool').length,0);
    assert.equal(store.events(job.id,'phone').filter(e=>e.type==='response_begin').length,3);
  }finally{store.close();}
});

test('scheduled HTTP520 retries remain bounded without losing the actual diagnostic',async()=>{
  const store=new JobStore(':memory:',new Vault(randomBytes(32)));const waits=[];let attempts=0;
  const provider={streamTurn:async()=>{attempts++;throw apiError({type:'about:blank',status:520,detail:'private response content'},520,'req_fixture_520');}};
  const runner=new JobRunner(store,provider,{definitions:[]},undefined,{sleep:async n=>waits.push(n)});
  try{const job=store.create('phone','request520',{schedule_id:'bounded-schedule',body:{model:'synthetic',input:[]},catalog:[]}).job;
    await runner.start(job.id,'phone');assert.equal(attempts,3);assert.deepEqual(waits,[5000,15000]);
    const last=store.events(job.id,'phone').at(-1);assert.equal(last.error.code,'provider_unavailable');
    assert.equal(last.error.diagnostic.status,520);assert.equal(last.error.diagnostic.request_id,'req_fixture_520');
    assert.match(last.text,/HTTP 520/);assert.equal(JSON.stringify(last).includes('private response content'),false);
    assert.equal(store.list('phone').length,1);assert.equal(store.events(job.id,'phone').filter(e=>e.type==='executed_tool').length,0);
  }finally{store.close();}
});

test('temporary subscription availability can recover; sharing limits and permissions are not retried',async()=>{
  const cases=[
    {body:{error:{code:'subscription_sharing_usage_unavailable'}},status:503,recover:true,attempts:2},
    {body:{error:{code:'subscription_sharing_usage_limit_exceeded'}},status:429,recover:false,attempts:1},
    {body:{detail:'permission denied'},status:403,recover:false,attempts:1}
  ];
  for(const entry of cases){
    const store=new JobStore(':memory:',new Vault(randomBytes(32)));let attempts=0;
    const runner=new JobRunner(store,{streamTurn:async()=>{if(++attempts===1||!entry.recover)throw apiError(entry.body,entry.status);return {output:[{type:'message',role:'assistant',content:[{type:'output_text',text:'Recovered'}]}]};}},{definitions:[]},undefined,{sleep:async()=>{}});
    try{const job=store.create('phone','request',{body:{model:'synthetic',input:[]},catalog:[]}).job;
      await runner.start(job.id,'phone');assert.equal(attempts,entry.attempts);assert.equal(store.get(job.id,'phone').status,entry.recover?'completed':'failed');
    }finally{store.close();}
  }
});

test('scheduled persistent overload is bounded and remains distinct from a local task failure',async()=>{
  const store=new JobStore(':memory:',new Vault(randomBytes(32)));let attempts=0;
  const runner=new JobRunner(store,{streamTurn:async()=>{attempts++;throw Object.assign(new Error('private raw body'),{code:'server_is_overloaded',status:200});}},{definitions:[]},undefined,{sleep:async()=>{}});
  try{const job=store.create('phone','request',{schedule_id:'bounded-schedule',body:{model:'synthetic',input:[]},catalog:[]}).job;
    await runner.start(job.id,'phone');assert.equal(attempts,3);
    const last=store.events(job.id,'phone').at(-1);assert.equal(last.error.code,'server_is_overloaded');assert.match(last.text,/ChatGPT is busy/);assert.equal(JSON.stringify(last).includes('private raw body'),false);
  }finally{store.close();}
});
