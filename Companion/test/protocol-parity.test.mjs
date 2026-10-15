import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {normalizeArguments} from '../src/tool-arguments.mjs';
const fixtures=JSON.parse(readFileSync(new URL('../../Sources/AssistantCore/Resources/ProtocolParity.json',import.meta.url),'utf8'));
test('Swift and computer consume the same argument behavior fixtures',()=>{
  for(const item of fixtures.normalization){
    if(item.error)assert.throws(()=>normalizeArguments(item.input,item.schema),item.name);
    else assert.deepEqual(JSON.parse(JSON.stringify(normalizeArguments(item.input,item.schema))),item.expected,item.name);
  }
});
import {randomBytes} from 'node:crypto';
import {Vault} from '../src/vault.mjs';
import {JobStore} from '../src/job-store.mjs';
test('shared receipt fixtures survive the actual encrypted operation store',()=>{
  const store=new JobStore(':memory:',new Vault(randomBytes(32)));
  try{
    const job=store.create('fixture-phone','receipt-contract',{turn_id:'fixture-turn',conversation_id:'fixture-chat'}).job;
    for(const receipt of fixtures.receipts){
      const call={id:receipt.callID,name:receipt.name,arguments:{}};
      store.beginOperation(job.id,call.id,call,'phone');store.finishOperation(job.id,call.id,receipt);
      const replay=store.beginOperation(job.id,call.id,call,'phone');
      assert.deepEqual(replay.result,receipt);
    }
  }finally{store.close();}
});
