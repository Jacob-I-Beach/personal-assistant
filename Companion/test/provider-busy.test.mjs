import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {Vault} from '../src/vault.mjs';
import {JobStore} from '../src/job-store.mjs';
import {JobRunner} from '../src/job-runner.mjs';

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

test('persistent overload is bounded and remains distinct from a local task failure',async()=>{
  const store=new JobStore(':memory:',new Vault(randomBytes(32)));let attempts=0;
  const runner=new JobRunner(store,{streamTurn:async()=>{attempts++;throw Object.assign(new Error('private raw body'),{code:'server_is_overloaded',status:200});}},{definitions:[]},undefined,{sleep:async()=>{}});
  try{const job=store.create('phone','request',{body:{model:'synthetic',input:[]},catalog:[]}).job;
    await runner.start(job.id,'phone');assert.equal(attempts,3);
    const last=store.events(job.id,'phone').at(-1);assert.equal(last.error.code,'server_is_overloaded');assert.match(last.text,/ChatGPT is busy/);assert.equal(JSON.stringify(last).includes('private raw body'),false);
  }finally{store.close();}
});
