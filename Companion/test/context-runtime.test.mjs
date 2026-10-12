import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {Vault} from '../src/vault.mjs';
import {JobStore} from '../src/job-store.mjs';
import {contextResult,hasContext} from '../src/context-runtime.mjs';

test('permitted snapshot reads and saved plans continue without a phone; missing sources stay phone-owned',()=>{
  const store=new JobStore(':memory:',new Vault(randomBytes(32))),job=store.create('fixture','context',{turn_id:'turn',body:{model:'fixture',input:[]},server_context:{history:[{message_id:'ABC',text:'A permitted source',complete:true}],memories:[{memory_id:'DEF',title:'Preference',text:'Use clear examples',complete:true}],coverage:'Current permitted snapshot'}}).job;
  try{
    assert.equal(hasContext({name:'read_history',arguments:{message_id:'abc',offset:'0'}},job),true);
    assert.equal(hasContext({name:'read_history',arguments:{message_id:'not-shared',offset:'0'}},job),false);
    const read=contextResult(store,{id:'read',name:'read_history',arguments:{message_id:'abc',offset:'2'}},job);assert.equal(read.output.text,'permitted source');
    contextResult(store,{id:'plan',name:'update_plan',arguments:{steps_json:JSON.stringify([{title:'Prepare the report',status:'in_progress'}])}},job);
    const task=contextResult(store,{id:'task',name:'read_task',arguments:{task_id:''}},job);assert.equal(task.output.plan[0].title,'Prepare the report');
  }finally{store.close();}
});
