import test from 'node:test';
import assert from 'node:assert/strict';
import https from 'node:https';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomBytes} from 'node:crypto';
import {Vault} from '../src/vault.mjs';
import {startCompanion} from '../src/server.mjs';

test('paired HTTPS jobs survive a lost client, preserve ownership and reconnect to the completed result',async()=>{
  const root=await mkdtemp(join(tmpdir(),'assistant-host-test-'));
  let release;
  const waiting=new Promise(resolve=>{release=resolve;});
  const host=await startCompanion({root,apiHost:'127.0.0.1',apiPort:0,setupPort:0,keepAwake:false,vault:new Vault(randomBytes(32)),
    provider:{getSession:async()=>({status:'connected',sharing:true,profileId:'synthetic'}),streamTurn:async()=>{await waiting;return {output:[{type:'message',role:'assistant',content:[{type:'output_text',text:'Completed without the phone.'}]}]};}},
    runtime:{definitions:[],available:async()=>true,supports:()=>false,summary:()=>''}});
  const request=(path,body,token)=>new Promise((resolve,reject)=>{
    const data=body===undefined?null:Buffer.from(JSON.stringify(body));
    const req=https.request({hostname:'127.0.0.1',port:host.apiPort,path,method:data?'POST':'GET',rejectUnauthorized:false,headers:{...(data?{'content-type':'application/json','content-length':data.length}:{}),...(token?{authorization:'Bearer '+token}:{})}},res=>{
      assert.equal(res.socket.getPeerCertificate().fingerprint256.replaceAll(':','').toLowerCase(),host.tls.fingerprint);
      const chunks=[];res.on('data',c=>chunks.push(c));res.on('end',()=>resolve({status:res.statusCode,body:JSON.parse(Buffer.concat(chunks))}));
    });req.on('error',reject);req.end(data);
  });
  try{
    const code=host.pairing.issue({baseURL:`https://127.0.0.1:${host.apiPort}`,fingerprint:host.tls.fingerprint,serverId:'synthetic'});
    const paired=await request('/v1/pair',{pairing_code:code.pairing_code,device_name:'Test phone'});assert.equal(paired.status,200);
    const token=paired.body.credential;
    assert.equal((await request('/v1/jobs')).status,401);
    const body={request_key:'one-turn',conversation_id:'chat',turn_id:'turn',profile_id:'synthetic',body:{model:'synthetic',input:[]},catalog:[]};
    const created=await request('/v1/jobs',body,token);assert.equal(created.status,201);
    const id=created.body.id;assert.equal((await request('/v1/jobs',body,token)).body.id,id);
    assert.equal((await request(`/v1/jobs/${id}/start`,{},token)).status,200);
    release();await host.runner.active.get(id)?.promise;
    const result=await request(`/v1/jobs/${id}/events?after=0`,undefined,token);
    assert.equal(result.body.job.status,'completed');assert.ok(result.body.events.some(e=>e.type==='continuation'));
    host.pairing.revoke(paired.body.device_id);
    assert.equal((await request(`/v1/jobs/${id}`,undefined,token)).status,401);
  }finally{release();await host.close();await rm(root,{recursive:true,force:true});}
});
