import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {randomBytes} from 'node:crypto';
import {Vault} from '../src/vault.mjs';
import {JobStore} from '../src/job-store.mjs';
import {BrowserRuntime} from '../src/browser-runtime.mjs';

test('real Edge tool inspects a synthetic page and reviews a bound observed control',async()=>{
  const server=http.createServer((_req,res)=>{res.writeHead(200,{'content-type':'text/html'});res.end('<!doctype html><title>Assistant browser fixture</title><h1>Browser tool check</h1><button onclick="this.textContent=\'Recorded\'">Record a choice</button>');});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const store=new JobStore(':memory:',new Vault(randomBytes(32))),job=store.create('fixture','browser',{body:{model:'fixture',input:[]}}).job;
  let reviews=0;const runtime=new BrowserRuntime({store,review:async(_job,_call,detail)=>{reviews++;assert.match(detail,/Record a choice/);}}),signal=new AbortController().signal;
  try{
    const initial=await runtime.execute({id:'open',name:'computer_browser',arguments:{action:'open',url:`http://127.0.0.1:${server.address().port}`,reason:'Synthetic fixture'}},job,signal);
    assert.equal(initial.output.title,'Assistant browser fixture');assert.ok(initial.output.files[0].bytes>1000);
    const button=initial.output.controls.find(item=>item.name==='Record a choice');assert.ok(button);
    const result=await runtime.execute({id:'click',name:'computer_browser',arguments:{action:'click',observation_id:initial.output.observation_id,element_id:button.element_id,reason:'Synthetic click'}},job,signal);
    assert.equal(reviews,1);assert.match(result.output.text,/Recorded/);
    await assert.rejects(runtime.execute({id:'stale',name:'computer_browser',arguments:{action:'click',observation_id:initial.output.observation_id,element_id:button.element_id,reason:'Stale click'}},job,signal),/Inspect/);
  }finally{await runtime.close();store.close();await new Promise(resolve=>server.close(resolve));}
});
