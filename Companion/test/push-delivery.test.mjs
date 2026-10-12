import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,randomBytes} from 'node:crypto';
import {Vault} from '../src/vault.mjs';
import {JobStore} from '../src/job-store.mjs';
import {Pairing} from '../src/pairing.mjs';
import {PushDelivery,activityPayload} from '../src/push-delivery.mjs';

test('server task state drives push completion; app disconnect does not imply completion',async()=>{
  const store=new JobStore(':memory:',new Vault(randomBytes(32))),pairing=new Pairing(store,store.vault);
  const code=pairing.issue({baseURL:'https://example.test',fingerprint:'0'.repeat(64),serverId:'fixture'}),owner=pairing.redeem(code.pairing_code,'Fixture').device_id;
  const job=store.create(owner,'task',{conversation_id:'fixture-chat',body:{model:'fixture',input:[]}}).job;
  const sent=[],push=new PushDelivery(store,{send:async value=>sent.push(value)});
  const {privateKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
  try{
    push.configure({team_id:'ABCDE12345',key_id:'FGHIJ67890',topic:'dev.test.assistant',private_key:privateKey.export({type:'pkcs8',format:'pem'})});
    push.register(owner,job.id,{environment:'development',topic:'dev.test.assistant',activity_token:'a'.repeat(64),device_token:'b'.repeat(64),notifications:true});push.close();
    store.status(job.id,'running','Checking sources');await push.deliver(job.id,{type:'activity',title:'Checking sources'});
    assert.equal(sent[0].payload.aps['content-state'].phase,'working');assert.equal(sent.length,1);
    store.status(job.id,'completed','Ready');await push.deliver(job.id,{type:'status',status:'completed'});
    assert.equal(sent[1].payload.aps['content-state'].phase,'ready');assert.equal(sent[2].headers['apns-push-type'],'alert');assert.equal(sent[2].payload.conversation_id,'fixture-chat');
    await push.deliver(job.id,{type:'status',status:'completed'});assert.equal(sent.filter(item=>item.headers['apns-push-type']==='alert').length,1);
    assert.equal(JSON.stringify(push.status()).includes('PRIVATE KEY'),false);
    pairing.revoke(owner);const count=sent.length;await push.deliver(job.id,{type:'status',status:'completed'});assert.equal(sent.length,count);
  }finally{push.close();store.close();}
});
test('ActivityKit uses Apple reference dates in Codable state and Unix time in its push envelope',()=>{
  const payload=activityPayload({status:'running'},{type:'activity',title:'Reading the document'});
  assert.ok(Math.abs(payload.aps.timestamp-payload.aps['content-state'].updatedAt-978307200)<2);
  assert.equal(payload.aps['content-state'].phase,'working');
  assert.equal(activityPayload({status:'completed'},{type:'activity',title:'Old step'}).aps['content-state'].phase,'ready');
});
