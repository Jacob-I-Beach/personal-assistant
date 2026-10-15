import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve,sep} from 'node:path';
import {randomBytes} from 'node:crypto';
import https from 'node:https';
import {Vault} from '../src/vault.mjs';
import {startCompanion} from '../src/server.mjs';

test('service restart after a long absence resumes one job, preserves its file and does not repeat the completed effect',async t=>{
  const root=await mkdtemp(join(tmpdir(),'assistant-continuity130-'));assert.ok(resolve(root).startsWith(resolve(tmpdir())+sep));
  const vault=new Vault(randomBytes(32));let host,turns=0,effects=0,fileID,entered;
  const paused=new Promise(resolve=>{entered=resolve;});
  const runtime={definitions:[{name:'save_fixture',description:'Synthetic durable effect',parameters:{type:'object',properties:{},required:[],additionalProperties:false}}],
    supports:name=>name==='save_fixture',available:async()=>true,title:()=>'',execute:async(call,job)=>{
      effects++;const file=host.store.saveFile(job.id,{filename:'retained.txt',role:'artifact'},Buffer.from('Exact saved output'));fileID=file.id;
      return {callID:call.id,name:call.name,succeeded:true,output:{status:'saved',files:[file]}};
    }};
  const provider={getSession:async()=>({status:'connected',sharing:true,profileId:'synthetic-profile'}),streamTurn:async({signal})=>{
    turns++;
    if(turns===1)return {output:[{type:'function_call',call_id:'write-once',name:'save_fixture',arguments:'{}'}]};
    if(turns===2){entered();await new Promise((resolve,reject)=>{signal.addEventListener('abort',()=>reject(signal.reason),{once:true});if(signal.aborted)reject(signal.reason);});}
    return {output:[{type:'message',role:'assistant',content:[{type:'output_text',text:'Finished from the saved state.'}]}]};
  }};
  const options={root,vault,provider,runtime,apiHost:'127.0.0.1',apiPort:0,setupPort:0,keepAwake:false};
  try{
    host=await startCompanion(options);
    const pairing=host.pairing.issue({baseURL:`https://127.0.0.1:${host.apiPort}`,fingerprint:host.tls.fingerprint,serverId:'fixture'});
    const phone=host.pairing.redeem(pairing.pairing_code,'Synthetic phone');
    const job=host.store.create(phone.device_id,'one-request',{profile_id:'synthetic-profile',title:'Synthetic long task',conversation_id:'chat',turn_id:'turn',body:{model:'synthetic',input:[]},catalog:[]}).job;
    host.runner.start(job.id,phone.device_id);await paused;assert.equal(effects,1);
    const fingerprint=host.tls.fingerprint;await host.close();host=null;
    t.mock.timers.enable({apis:['Date'],now:Date.now()+90*60*1000});
    host=await startCompanion(options);
    for(let i=0;i<300&&host.store.get(job.id,phone.device_id).status!=='completed';i++)await new Promise(resolve=>setTimeout(resolve,10));
    assert.equal(host.store.get(job.id,phone.device_id).status,'completed');assert.equal(effects,1);assert.equal(turns,3);assert.equal(host.tls.fingerprint,fingerprint);
    assert.equal(host.store.list(phone.device_id).length,1);
    const bytes=await new Promise((resolveRequest,reject)=>{
      const request=https.get({hostname:'127.0.0.1',port:host.apiPort,path:`/v1/jobs/${job.id}/files/${fileID}`,rejectUnauthorized:false,headers:{authorization:'Bearer '+phone.credential}},response=>{
        assert.equal(response.statusCode,200);assert.equal(response.socket.getPeerCertificate().fingerprint256.replaceAll(':','').toLowerCase(),fingerprint);
        const chunks=[];response.on('data',data=>chunks.push(data));response.on('end',()=>resolveRequest(Buffer.concat(chunks)));
      });request.on('error',reject);
    });
    assert.equal(bytes.toString(),'Exact saved output');
  }finally{await host?.close();await rm(root,{recursive:true,force:true});}
});
