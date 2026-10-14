import test from 'node:test';
import assert from 'node:assert/strict';
import {ServiceReadiness} from '../src/service-readiness.mjs';
test('a slow optional service does not block status or spawn duplicate probes',async()=>{
  let release,calls=0,now=10000;
  const probe=new ServiceReadiness(async()=>{calls++;return new Promise(resolve=>{release=resolve;});},{now:()=>now,ttl:1000});
  assert.equal(probe.snapshot().state,'checking');assert.equal(probe.snapshot().available,null);
  await Promise.resolve();assert.equal(calls,1);release(true);await probe.pending;
  assert.equal(probe.snapshot().state,'ready');assert.equal(calls,1);
  now+=1001;assert.equal(probe.snapshot().state,'checking');await Promise.resolve();release(false);await probe.pending;
  assert.equal(probe.snapshot().state,'unavailable');probe.close();
});
test('optional service errors remain scoped to computation readiness',async()=>{
  const probe=new ServiceReadiness(async()=>{throw new Error('Docker unavailable');});
  probe.snapshot();await probe.pending;assert.equal(probe.snapshot().available,false);assert.equal(probe.snapshot().state,'unavailable');probe.close();
});
