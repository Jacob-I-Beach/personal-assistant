import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {Vault} from '../src/vault.mjs';
import {JobStore} from '../src/job-store.mjs';
import {JobRunner} from '../src/job-runner.mjs';
import {Scheduler} from '../src/scheduler.mjs';

test('a reviewed schedule owns one restricted run per occurrence and never bursts old missed runs',async()=>{
  const store=new JobStore(':memory:',new Vault(randomBytes(32)));let now=1000000000000,requests=0;
  const provider={streamTurn:async({body})=>{requests++;assert.ok(body.tools.every(tool=>tool.type==='web_search'));return {output:[{type:'message',role:'assistant',content:[{type:'output_text',text:'Scheduled result'}]}]};}};
  const runner=new JobRunner(store,provider,{definitions:[],supports:()=>false});
  const source=store.create('phone','source',{profile_id:'account',body:{model:'synthetic',input:[],tools:[{type:'function',name:'compose_text_message'},{type:'web_search'}]},catalog:[{name:'compose_text_message'}]}).job;
  const input=store.saveFile(source.id,{filename:'selected.csv',role:'input',contains_health_data:true},Buffer.from('value\n1'));
  const scheduler=new Scheduler(store,runner,{now:()=>now,mayRun:(_,profile)=>profile==='account'});
  const args={request_key:'reviewed-schedule',source_job_id:source.id,title:'Check a public page',prompt:'Compare current public information.',run_at:[now+1000,now+86400000]};
  const schedule=scheduler.create('phone',args);assert.equal(scheduler.create('phone',args).id,schedule.id);
  const later=store.saveFile(source.id,{filename:'added-later.csv',role:'input'},Buffer.from('value\n2'));
  now+=2000;await scheduler.tick();await Promise.all([...runner.active.values()].map(value=>value.promise));await scheduler.tick();await scheduler.tick();
  assert.equal(requests,1);let state=scheduler.list('phone')[0];assert.equal(state.runs[0].status,'completed');
  assert.deepEqual(store.get(state.runs[0].job_id,'phone').payload.catalog,[]);
  assert.equal(store.get(state.runs[0].job_id,'phone').payload.contains_health_data,true);
  const files=store.files(state.runs[0].job_id,'phone');assert.ok(files.some(file=>file.id===input.id));assert.ok(!files.some(file=>file.id===later.id));
  now+=2*86400000;await scheduler.tick();state=scheduler.list('phone')[0];assert.equal(state.runs[1].status,'missed');assert.equal(requests,1);assert.equal(state.enabled,false);
  store.close();
});
