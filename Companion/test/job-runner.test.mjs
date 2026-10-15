import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { Vault } from '../src/vault.mjs';
import { JobStore } from '../src/job-store.mjs';
import { JobRunner } from '../src/job-runner.mjs';

const runtime = {supports: () => false, summary: () => 'Synthetic runtime'};

test('web receipts and citation positions are durable before a response finishes', async () => {
  const store = new JobStore(':memory:', new Vault(randomBytes(32)));
  let release, started;
  const waiting = new Promise(resolve => { release = resolve; });
  const streaming = new Promise(resolve => { started = resolve; });
  const web = {id:'web1',type:'web_search_call',status:'in_progress'};
  const completed = {...web,status:'completed',action:{type:'search',query:'synthetic trail comparison'}};
  const provider = {streamTurn: async ({onEvent}) => {
    await onEvent({type:'response.output_item.added',output_index:0,item:web});
    await onEvent({type:'response.web_search_call.searching',output_index:0,item_id:web.id});
    await onEvent({type:'response.output_item.done',output_index:0,item:completed});
    await onEvent({type:'response.output_item.added',output_index:1,item:{id:'answer',type:'message',phase:'final_answer'}});
    await onEvent({type:'response.output_text.delta',output_index:1,content_index:0,item_id:'answer',delta:'A partial answer'});
    await onEvent({type:'response.output_text.annotation.added',output_index:1,content_index:0,item_id:'answer',annotation:{type:'url_citation',url:'https://example.test/trails',title:'Trail guide'}});
    await onEvent({type:'response.output_item.added',output_index:2,item:{id:'private',type:'reasoning',encrypted_content:'never-publish-this'}});
    started(); await waiting;
    return {output:[completed,{id:'answer',type:'message',role:'assistant',content:[{type:'output_text',text:'A complete answer'}]}]};
  }};
  const runner = new JobRunner(store, provider, runtime);
  const job = store.create('phone','research',{body:{model:'synthetic',input:[]},catalog:[]}).job;
  const done = runner.start(job.id,'phone');
  await streaming;
  const events = store.events(job.id,'phone');
  assert.equal(store.get(job.id,'phone').status,'running');
  assert.equal(events.filter(e=>e.type==='web_activity').length,3);
  assert.equal(events.findLast(e=>e.type==='web_activity').item.action.query,'synthetic trail comparison');
  assert.equal(events.find(e=>e.type==='text_delta').output_index,1);
  assert.equal(events.find(e=>e.type==='annotation').item_id,'answer');
  assert.equal(JSON.stringify(events).includes('never-publish-this'),false);
  assert.equal(events.some(e=>e.type==='continuation'),false);
  release(); await done;
  assert.equal(store.get(job.id,'phone').status,'completed');
  store.close();
});

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
  assert.equal(store.get(job.id, 'phone').status, 'running');
  const result = {succeeded: true, output: {status: 'sent', delivery_confirmed: false}};
  runner.answer(job.id, 'phone', 'review-1', result);
  await done;
  assert.ok(calls >= 2 && calls <= 3, 'an answer arriving during independent work gets its own continuation'); assert.equal(store.get(job.id, 'phone').status, 'completed');
  assert.equal(store.events(job.id, 'phone').filter(e => e.type === 'executed_tool').length, 1);
  store.close();
});
