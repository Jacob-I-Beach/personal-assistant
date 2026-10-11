import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { Vault } from '../src/vault.mjs';
import { JobStore } from '../src/job-store.mjs';
import { JobRunner } from '../src/job-runner.mjs';

const runtime = {supports: () => false, summary: () => 'Synthetic runtime'};

test('the host completes a model response after the phone subscriber disconnects', async () => {
  const store = new JobStore(':memory:', new Vault(randomBytes(32)));
  let continueResponse;
  const waiting = new Promise(resolve => { continueResponse = resolve; });
  const provider = {streamTurn: async ({onEvent}) => {
    await onEvent({type: 'response.output_text.delta', delta: 'First '});
    await waiting;
    await onEvent({type: 'response.output_text.delta', delta: 'finished'});
    return {output: [{type: 'message', role: 'assistant', content: [{type: 'output_text', text: 'First finished'}]}]};
  }};
  const runner = new JobRunner(store, provider, runtime);
  const job = store.create('phone', 'request', {body: {model: 'synthetic', input: []}, catalog: []}).job;
  const listener = () => {};
  runner.on('event', listener);
  const completed = runner.start(job.id, 'phone');
  runner.off('event', listener); continueResponse();
  await completed;
  assert.equal(store.get(job.id, 'phone').status, 'completed');
  assert.equal(store.events(job.id, 'phone').filter(e => e.type === 'text_delta').map(e => e.text).join(''), 'First finished');
  store.close();
});

test('phone work pauses durably and resumes exactly once after its actual receipt', async () => {
  const store = new JobStore(':memory:', new Vault(randomBytes(32)));
  let calls = 0;
  const provider = {streamTurn: async () => ++calls === 1 ? {output: [{type: 'function_call', call_id: 'review-1', name: 'compose_text_message', arguments: '{"body":"Synthetic draft"}'}]} : {output: [{type: 'message', role: 'assistant', content: [{type: 'output_text', text: 'Sent through the reviewed composer.'}]}]}};
  const runner = new JobRunner(store, provider, runtime);
  const job = store.create('phone', 'request', {conversation_id: 'synthetic-chat', turn_id: 'synthetic-turn', body: {model: 'synthetic', input: []}, catalog: [{name: 'compose_text_message', description: 'Review a message'}]}).job;
  const waiting = new Promise(resolve => runner.on('event', (_, event) => { if (event.type === 'phone_request') resolve(); }));
  const done = runner.start(job.id, 'phone');
  await waiting;
  assert.equal(store.get(job.id, 'phone').status, 'waiting_for_phone');
  const result = {succeeded: true, output: {status: 'sent', delivery_confirmed: false}};
  runner.answer(job.id, 'phone', 'review-1', result);
  await done;
  assert.equal(calls, 2); assert.equal(store.get(job.id, 'phone').status, 'completed');
  assert.equal(store.events(job.id, 'phone').filter(e => e.type === 'executed_tool').length, 1);
  store.close();
});
