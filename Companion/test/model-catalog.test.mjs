import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {JobStore} from '../src/job-store.mjs';
import {Vault} from '../src/vault.mjs';
import {ModelCatalog} from '../src/model-catalog.mjs';

function fixture(){
  const store=new JobStore(':memory:',new Vault(randomBytes(32)));let profile='a',failure=false,calls=0;
  const provider={getSession:async()=>({status:'connected',sharing:true,profileId:profile}),listModels:async()=>{calls++;if(failure)throw Object.assign(new Error('secret provider body'),{status:520});return[{slug:profile+'-model',displayName:'Model '+profile,contextWindow:252000}];}};
  return {store,provider,catalog:new ModelCatalog(store,provider),get calls(){return calls;},set profile(value){profile=value;},set failure(value){failure=value;}};
}
test('successful model choices survive failure and process restart without claiming freshness',async()=>{
  const f=fixture();try{
    assert.equal((await f.catalog.load()).catalog.state,'ready');f.failure=true;
    const failed=await f.catalog.load({force:true});assert.equal(failed.catalog.state,'stale');assert.equal(failed.models[0].slug,'a-model');assert.equal(failed.catalog.http_status,520);assert.ok(!JSON.stringify(failed).includes('secret'));
    const restarted=new ModelCatalog(f.store,f.provider);assert.equal(restarted.snapshot('a').models.length,1);
    assert.ok(!f.store.db.prepare('SELECT data FROM model_catalogs').get().data.includes(Buffer.from('a-model')));
  }finally{f.store.close();}
});
test('never leak another account catalog and never treat an empty failed list as fresh',async()=>{
  const f=fixture();try{await f.catalog.load();f.profile='b';f.failure=true;const value=await f.catalog.load();assert.deepEqual(value.models,[]);assert.equal(value.profile_id,'b');assert.equal(value.catalog.state,'unavailable');}finally{f.store.close();}
});
test('automatic refresh reuses cache but explicit refresh checks and recovers',async()=>{
  const f=fixture();try{await f.catalog.load();await f.catalog.load();assert.equal(f.calls,1);f.failure=true;await f.catalog.load({force:true});await f.catalog.load();assert.equal(f.calls,2);f.failure=false;assert.equal((await f.catalog.load({force:true})).catalog.state,'ready');assert.equal(f.calls,3);}finally{f.store.close();}
});
test('account switch during a response does not commit mismatched models',async()=>{
  const f=fixture();try{f.provider.listModels=async()=>{f.profile='b';return[{slug:'a',displayName:'A'}];};const value=await f.catalog.load();assert.equal(value.catalog.state,'unavailable');assert.equal(f.catalog.snapshot('a').models.length,0);assert.equal(f.catalog.snapshot('b').models.length,0);}finally{f.store.close();}
});
