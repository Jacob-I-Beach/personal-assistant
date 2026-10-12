import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomBytes} from 'node:crypto';
import {Vault} from '../src/vault.mjs';
import {JobStore} from '../src/job-store.mjs';
import {HostRuntime} from '../src/host-runtime.mjs';

async function fixture(){
  const root=await mkdtemp(join(tmpdir(),'assistant-host-tools-')),store=new JobStore(':memory:',new Vault(randomBytes(32)));
  const job=store.create('fixture','tools',{body:{model:'fixture',input:[]}}).job;
  const runtime=new HostRuntime({root:join(root,'work'),store,compute:{definitions:[],supports:()=>false,available:async()=>true,summary:()=>''}});
  return {root,store,job,runtime,signal:new AbortController().signal,async close(){await runtime.close();store.close();await rm(root,{recursive:true,force:true});}};
}
test('computer folder scope and exact versions prevent an unreviewed or stale host write',async()=>{
  const f=await fixture();try{
    const outside=join(f.root,'outside.txt');await writeFile(outside,'original');
    await assert.rejects(f.runtime.execute({id:'read',name:'read_computer_file',arguments:{path:outside,offset:0,as_artifact:false}},f.job,f.signal),/Connect/);
    f.runtime.approve=async()=>({output:{status:'approved'}});
    await f.runtime.execute({id:'connect',name:'connect_computer_folder',arguments:{path:f.root,access:'read',reason:'Fixture folder'}},f.job,f.signal);
    const read=await f.runtime.execute({id:'read2',name:'read_computer_file',arguments:{path:outside,offset:0,as_artifact:false}},f.job,f.signal);
    assert.equal(read.output.text,'original');
    await assert.rejects(f.runtime.execute({id:'write',name:'write_computer_file',arguments:{path:outside,content:'changed',expected_sha256:read.output.sha256}},f.job,f.signal),/Connect/);
    await f.runtime.execute({id:'connect2',name:'connect_computer_folder',arguments:{path:f.root,access:'write',reason:'Fixture edit'}},f.job,f.signal);
    await writeFile(outside,'edited outside');
    await assert.rejects(f.runtime.execute({id:'stale',name:'write_computer_file',arguments:{path:outside,content:'lost edit',expected_sha256:read.output.sha256}},f.job,f.signal),/changed/);
    assert.equal(await readFile(outside,'utf8'),'edited outside');
  }finally{await f.close();}
});
test('host command cancellation is honored before a process is created',async()=>{
  const f=await fixture();let ran=0,review;
  try{f.runtime.approve=async(_job,_call,value)=>{review=value;return {output:{status:'cancelled'}};};f.runtime.executeProcess=async()=>{ran++;};
    await assert.rejects(f.runtime.execute({id:'command',name:'run_computer_command',arguments:{command:'Write-Output fixture',working_directory:null,reason:'Synthetic command',timeout_seconds:5}},f.job,f.signal),/not approved/);
    assert.equal(ran,0);assert.match(review.detail,/Write-Output fixture/);
    f.runtime.approve=async()=>({output:{status:'approved'}});f.runtime.executeProcess=async(_exe,args)=>{ran++;assert.ok(args.includes('-EncodedCommand'));return {exit_code:0,stdout:'fixture',stderr:'',timed_out:false,output_truncated:false};};
    const result=await f.runtime.execute({id:'approved',name:'run_computer_command',arguments:{command:'Write-Output fixture',working_directory:null,reason:'Synthetic command',timeout_seconds:5}},f.job,f.signal);
    assert.equal(result.succeeded,true);assert.equal(ran,1);
  }finally{await f.close();}
});
test('computer-generated files retain the task Health classification',async()=>{
  const f=await fixture();try{
    f.job.payload.contains_health_data=true;
    const result=await f.runtime.execute({id:'private-file',name:'write_computer_file',arguments:{path:'synthetic-private-note.txt',content:'Synthetic labelled content',expected_sha256:null}},f.job,f.signal);
    assert.equal(result.containsHealthData,true);assert.equal(result.output.files[0].contains_health_data,true);
  }finally{await f.close();}
});
test('desktop actions require the observation from the immediately inspected window',async()=>{
  if(process.platform!=='win32')return;
  const f=await fixture();let actions=0;
  try{f.runtime.approve=async()=>({output:{status:'approved'}});f.runtime.executeProcess=async(_exe,_args,{input})=>{const value=JSON.parse(input);if(value.action!=='snapshot'){actions++;assert.equal(value.expected_window_id,'42');}return {exit_code:0,stdout:JSON.stringify({window:'Synthetic window',window_id:'42',controls:[],width:100,height:100}),stderr:''};};
    const snapshot=await f.runtime.execute({id:'observe',name:'computer_desktop',arguments:{action:'snapshot'}},f.job,f.signal);
    await assert.rejects(f.runtime.execute({id:'bad',name:'computer_desktop',arguments:{action:'click',observation_id:'guessed'}},f.job,f.signal),/fresh/);
    await f.runtime.execute({id:'click',name:'computer_desktop',arguments:{action:'click',observation_id:snapshot.output.observation_id,x:10,y:10,reason:'Fixture click'}},f.job,f.signal);
    assert.equal(actions,1);
    await assert.rejects(f.runtime.execute({id:'repeat',name:'computer_desktop',arguments:{action:'click',observation_id:snapshot.output.observation_id}},f.job,f.signal),/fresh/);
  }finally{await f.close();}
});
