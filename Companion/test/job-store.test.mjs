import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { Vault } from '../src/vault.mjs';
import { JobStore } from '../src/job-store.mjs';

test('work and progress survive a disconnected subscriber without creating another job', () => {
  const vault = new Vault(randomBytes(32)), store = new JobStore(':memory:', vault);
  const payload = {model: 'synthetic', prompt: 'A private synthetic request'};
  const first = store.create('phone-a', 'request-a', payload);
  store.append(first.job.id, {type: 'text_delta', text: 'First part'});
  const cursor = store.get(first.job.id, 'phone-a').cursor;
  // No subscriber is attached while the worker records more output.
  store.append(first.job.id, {type: 'text_delta', text: 'Final part'});
  store.status(first.job.id, 'completed', 'Ready');
  const second = store.create('phone-a', 'request-a', payload);
  assert.equal(second.created, false); assert.equal(first.job.id, second.job.id);
  assert.equal(second.job.status, 'completed');
  assert.deepEqual(store.events(first.job.id, 'phone-a', cursor).map(x => x.type), ['text_delta', 'status']);
  assert.throws(() => store.get(first.job.id, 'another-phone'));
  assert.throws(() => store.create('phone-a', 'request-a', {...payload, prompt: 'Changed'}));
  const raw = store.db.prepare('SELECT data FROM jobs').get().data;
  assert.equal(Buffer.from(raw).includes(Buffer.from('private synthetic')), false);
  store.close();
});
test('Stop arriving before a lost create response prevents that request from starting later',()=>{
  const store=new JobStore(':memory:',new Vault(randomBytes(32)));
  assert.equal(store.cancelRequest('phone','lost-request'),null);
  const job=store.create('phone','lost-request',{title:'Stopped request',body:{model:'synthetic',input:[{text:'private input'}]}}).job;
  assert.equal(job.status,'cancelled');
  assert.equal(store.list('phone')[0].payload.body.input,undefined);
  assert.equal(store.metadata(job.id,'phone').status,'cancelled');
  assert.throws(()=>store.metadata(job.id,'different-phone'));
  store.close();
});

test('pending phone operations and versioned artifacts reject conflicting replays', () => {
  const store = new JobStore(':memory:', new Vault(randomBytes(32)));
  const id = store.create('phone', 'request', {prompt: 'Synthetic'}).job.id;
  store.beginOperation(id, 'send-1', {name: 'compose_text_message', arguments: {body: 'Synthetic'}}, 'phone');
  const result = {status: 'sent', delivery_confirmed: false};
  store.finishOperation(id, 'send-1', result);
  assert.deepEqual(store.finishOperation(id, 'send-1', result), result);
  assert.throws(() => store.finishOperation(id, 'send-1', {status: 'cancelled'}));
  const first = store.saveFile(id, {filename: 'report.txt'}, Buffer.from('First'));
  const next = store.saveFile(id, first, Buffer.from('Revised'), 1);
  assert.equal(next.id, first.id); assert.equal(next.version, 2);
  assert.throws(() => store.saveFile(id, first, Buffer.from('Stale'), 1));
  assert.equal(store.file(id, 'phone', first.id, 1).data.toString(), 'First');
  assert.equal(store.file(id, 'phone', first.id).data.toString(), 'Revised');
  store.close();
});

test('saved records are authenticated for their specific purpose', () => {
  const vault = new Vault(randomBytes(32)), bytes = vault.sealJSON({value: 42}, 'record-a');
  assert.deepEqual(vault.openJSON(bytes, 'record-a'), {value: 42});
  assert.throws(() => vault.openJSON(bytes, 'record-b'));
  bytes[bytes.length - 1] ^= 1;
  assert.throws(() => vault.openJSON(bytes, 'record-a'));
});
