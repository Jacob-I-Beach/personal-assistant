import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {Vault} from '../src/vault.mjs';
import {JobStore} from '../src/job-store.mjs';
import {ComputeRuntime} from '../src/compute-runtime.mjs';

test('inspection outputs can be published without Docker, byte changes or duplicate attachments',async()=>{
  const store=new JobStore(':memory:',new Vault(randomBytes(32)));
  const runtime=new ComputeRuntime({root:'.',store,docker:'not-needed'});
  const job=store.create('phone','screenshot',{body:{model:'synthetic',input:[]}}).job;
  const image=store.saveFile(job.id,{filename:'computer-screen.png',role:'inspection'},Buffer.from('synthetic image bytes'));
  const other=store.create('another-phone','another',{body:{model:'synthetic',input:[]}}).job;
  const foreign=store.saveFile(other.id,{filename:'other.png',role:'inspection'},Buffer.from('different source'));
  try{
    const call={id:'show-image',name:'publish_task_files',arguments:{file_ids:[image.id],caption:'The requested screen'}};
    const result=await runtime.execute(call,job,new AbortController().signal),published=result.output.presented_files[0];
    assert.equal(result.succeeded,true);assert.notEqual(published.id,image.id);assert.equal(published.role,'artifact');
    assert.deepEqual(store.file(job.id,job.owner,published.id).data,store.file(job.id,job.owner,image.id).data);
    assert.equal(store.file(job.id,job.owner,image.id).metadata.role,'inspection');
    const again=await runtime.execute({...call,id:'show-again'},job,new AbortController().signal);
    assert.equal(again.output.presented_files[0].id,published.id);
    await assert.rejects(()=>runtime.execute({...call,arguments:{...call.arguments,file_ids:[foreign.id]}},job,new AbortController().signal));
  }finally{store.close();}
});
