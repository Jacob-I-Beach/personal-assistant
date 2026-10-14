import test from 'node:test';
import assert from 'node:assert/strict';
import https from 'node:https';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve,sep} from 'node:path';
import {randomBytes} from 'node:crypto';
import {Vault} from '../src/vault.mjs';
import {startCompanion} from '../src/server.mjs';
import {JobStore} from '../src/job-store.mjs';

const final={output:[{type:'message',role:'assistant',content:[{type:'output_text',text:'Synthetic completed'}]}]};
const definition={name:'synthetic_effect',description:'Test only',parameters:{type:'object',properties:{},required:[],additionalProperties:false}};
const waitFor=async predicate=>{for(let i=0;i<400;i++){if(predicate())return;await new Promise(r=>setTimeout(r,10));}throw new Error('Fixture did not reach the expected state');};

test('real revoke endpoint stops owned children and queued recovery, while retaining actual receipts after reopen',async()=>{
  const root=await mkdtemp(join(tmpdir(),'assistant-audit-server-'));
  assert.ok(resolve(root).startsWith(resolve(tmpdir())+sep));
  const vault=new Vault(randomBytes(32));let starts=0,toolSignal,releaseTool;
  const provider={getSession:async()=>({status:'connected',sharing:true,profileId:'synthetic'}),streamTurn:async({signal})=>{
    starts++;await new Promise((resolve,reject)=>{if(signal.aborted)reject(signal.reason);else signal.addEventListener('abort',()=>reject(signal.reason),{once:true});});return final;
  }};
  const runtime={definitions:[definition],available:async()=>true,supports:()=>true,summary:()=>'',execute:async(call,job,signal)=>{
    toolSignal=signal;await new Promise(r=>{releaseTool=r;});return {callID:call.id,name:call.name,succeeded:true,output:{status:'saved'}};
  }};
  let host=await startCompanion({root,apiHost:'127.0.0.1',apiPort:0,setupPort:0,keepAwake:false,vault,provider,runtime});
  const tls=host.tls;
  const request=(path,body,token)=>new Promise((resolveRequest,reject)=>{
    const data=body===undefined?undefined:Buffer.from(JSON.stringify(body));
    const req=https.request({hostname:'127.0.0.1',port:host.apiPort,path,method:data?'POST':'GET',rejectUnauthorized:false,
      headers:{...(data?{'content-type':'application/json','content-length':data.length}:{}),...(token?{authorization:'Bearer '+token}:{})}},res=>{
      assert.equal(res.socket.getPeerCertificate().fingerprint256.replaceAll(':','').toLowerCase(),tls.fingerprint);
      const chunks=[];res.on('data',c=>chunks.push(c));res.on('end',()=>resolveRequest({status:res.statusCode,body:JSON.parse(Buffer.concat(chunks))}));
    });req.on('error',reject);req.end(data);
  });
  try {
    const code=host.pairing.issue({baseURL:`https://127.0.0.1:${host.apiPort}`,fingerprint:tls.fingerprint,serverId:'synthetic'});
    const phone=(await request('/v1/pair',{pairing_code:code.pairing_code,device_name:'Synthetic'})).body;
    const payload=key=>({request_key:key,conversation_id:'chat',turn_id:'turn',profile_id:'synthetic',start_when_ready:true,expected_file_ids:[],body:{model:'synthetic',input:[]},catalog:[]});
    for(let i=0;i<4;i++)assert.equal((await request('/v1/jobs',payload('active-'+i),phone.credential)).status,201);
    await waitFor(()=>starts===4);
    const queued=(await request('/v1/jobs',payload('queued'),phone.credential)).body;
    assert.equal(host.store.get(queued.id,phone.device_id).status,'queued');
    const child=(await request('/v1/tool-sessions',{request_key:'turn',conversation_id:'chat'},phone.credential)).body;
    const started=await request(`/v1/jobs/${child.id}/execute-tool`,{id:'effect',name:'synthetic_effect',arguments:{}},phone.credential);
    assert.equal(started.status,200);
    await waitFor(()=>!!toolSignal);
    const page=await fetch(host.setupURL),html=await page.text();
    const csrf=html.match(/name="csrf-token" content="([^"]+)"/)?.[1];assert.ok(csrf);
    const revoke=await fetch(host.setupURL+'/api/revoke',{method:'POST',headers:{cookie:page.headers.get('set-cookie').split(';')[0],origin:host.setupURL,'x-assistant-csrf':csrf,'content-type':'application/json'},body:JSON.stringify({device_id:phone.device_id})});
    assert.equal(revoke.status,200);assert.equal(toolSignal.aborted,true);
    releaseTool();await waitFor(()=>host.runner.active.size===0);
    assert.equal((await request('/v1/jobs',payload('after-revoke'),phone.credential)).status,401);
    assert.equal(host.store.get(queued.id,phone.device_id).status,'cancelled');
    const beforeClose=starts;await host.close();host=null;
    // A restart executes the same production recovery path with the revoked
    // owner persisted. No provider request can be admitted after revocation.
    host=await startCompanion({root,apiHost:'127.0.0.1',apiPort:0,setupPort:0,keepAwake:false,vault,tls,provider,runtime});
    assert.equal(starts,beforeClose);
    assert.equal(host.store.operation(child.id,'effect').result.succeeded,true);
    assert.equal(host.store.controlled(child.id).owner,phone.device_id);
  } finally {releaseTool?.();await host?.close();await rm(root,{recursive:true,force:true});}
});

test('failed terminal publication stays atomic across a real database reopen',async()=>{
  const root=await mkdtemp(join(tmpdir(),'assistant-audit-db-'));
  assert.ok(resolve(root).startsWith(resolve(tmpdir())+sep));
  const vault=new Vault(randomBytes(32)),path=join(root,'work.db');let store=new JobStore(path,vault);
  try {
    const job=store.create('phone','turn',{body:{model:'synthetic'}}).job;
    const seal=vault.sealJSON.bind(vault);
    vault.sealJSON=(value,scope)=>{if(value.type==='status'&&value.status==='completed')throw new Error('Injected terminal persistence failure');return seal(value,scope);};
    assert.throws(()=>store.status(job.id,'completed','Ready'));
    vault.sealJSON=seal;store.close();store=new JobStore(path,vault);
    assert.equal(store.get(job.id,'phone').status,'queued');assert.equal(store.events(job.id,'phone').at(-1).status,'queued');
    store.status(job.id,'completed','Ready');store.close();store=new JobStore(path,vault);
    assert.equal(store.get(job.id,'phone').status,'completed');assert.equal(store.events(job.id,'phone').at(-1).status,'completed');
  } finally {store.close();await rm(root,{recursive:true,force:true});}
});
