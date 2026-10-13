import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Vault } from '../src/vault.mjs';
import { JobStore } from '../src/job-store.mjs';

test('a returning phone can page through saved work and files after a long absence and store reopen', async t => {
  const root = await mkdtemp(join(tmpdir(), 'assistant-replay-'));
  const path = join(root, 'synthetic.sqlite'), vault = new Vault(randomBytes(32));
  let store = new JobStore(path, vault);
  try {
    t.mock.timers.enable({apis:['Date'],now:Date.UTC(2026,0,1)});
    const payload = {body:{model:'synthetic',input:[]}}, owner = 'synthetic-phone';
    const job = store.create(owner, 'original-request', payload).job;
    const seenCursor = job.cursor;
    // More than one response page accumulates with no phone subscriber.
    for(let i=0;i<450;i++) store.append(job.id,{type:'text_delta',text:String(i)});
    const artifact = store.saveFile(job.id,{filename:'result.txt',role:'artifact'},Buffer.from('Saved result'));
    store.status(job.id,'completed','Ready');
    store.close();
    t.mock.timers.setTime(Date.now()+90*60*1000);
    store = new JobStore(path,vault);
    const restored = store.get(job.id,owner);
    assert.equal(restored.status,'completed');
    let cursor = seenCursor, events = [];
    while(cursor<restored.cursor){
      const page = store.events(job.id,owner,cursor);
      assert.ok(page.length>0); events.push(...page); cursor=page.at(-1).seq;
    }
    assert.equal(events.filter(e=>e.type==='text_delta').length,450);
    assert.equal(new Set(events.map(e=>e.seq)).size,events.length);
    assert.equal(store.file(job.id,owner,artifact.id).data.toString(),'Saved result');
    const duplicate = store.create(owner,'original-request',payload);
    assert.equal(duplicate.created,false); assert.equal(duplicate.job.id,job.id);
  } finally { store.close(); await rm(root,{recursive:true,force:true}); }
});
