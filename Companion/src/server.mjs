import http from 'node:http';
import https from 'node:https';
import {readFile,mkdir,appendFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {networkInterfaces} from 'node:os';
import {randomBytes,createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import QRCode from 'qrcode';
import {createChatGPT} from '@siwc/local';
import {Vault,credentialEncryption} from './vault.mjs';
import {JobStore} from './job-store.mjs';
import {JobRunner} from './job-runner.mjs';
import {ComputeRuntime,computerTools} from './compute-runtime.mjs';
import {Pairing} from './pairing.mjs';
import {certificate} from './certificate.mjs';
import {jsonBody,jsonReply,validateJob} from './http-helpers.mjs';
import {Scheduler} from './scheduler.mjs';

const assets=fileURLToPath(new URL('../ui/',import.meta.url));
const terminal=new Set(['completed','failed','cancelled','interrupted']);
const safeFileName=name=>typeof name==='string'&&name.length>0&&name.length<180&&!/[\\/:\x00-\x1f]/.test(name)&&!['.','..'].includes(name);
function openBrowser(url) {
  const address=new URL(url);
  if(address.origin!=='https://auth.openai.com'&&address.hostname!=='127.0.0.1')throw new Error('Unexpected browser destination.');
  const child=spawn(join(process.env.SystemRoot??'C:\\Windows','System32','rundll32.exe'),['url.dll,FileProtocolHandler',url],{windowsHide:true,stdio:'ignore',shell:false});child.on('error',()=>{});
}
function addresses(port) {
  return Object.entries(networkInterfaces()).flatMap(([name,items])=>(items??[]).filter(item=>!item.internal&&item.family==='IPv4'&&!/vEthernet|Docker|WSL|VMware|VirtualBox|Radmin|Hamachi/i.test(name)).map(item=>({label:name,url:`https://${item.address}:${port}`})))
    .sort((a,b)=>Number(/tailscale/i.test(b.label))-Number(/tailscale/i.test(a.label)));
}
function publicJob(job) {return {id:job.id,request_key:job.requestKey,status:job.status,cursor:job.cursor,created_at:job.createdAt,updated_at:job.updatedAt,title:String(job.payload.title??'Assistant task').slice(0,160),model:job.payload.body?.model};}

export async function startCompanion(options={}) {
  const root=resolve(options.root??join(process.env.LOCALAPPDATA??'.','PersonalAssistantCompanion'));
  await mkdir(root,{recursive:true});
  const vault=options.vault??await Vault.open(root), tls=options.tls??await certificate(root);
  const store=new JobStore(join(root,'work.db'),vault),pairing=new Pairing(store,vault);
  const runtime=options.runtime??new ComputeRuntime({root:join(root,'temporary-executions'),store});
  const provider=options.provider??createChatGPT({appName:'Personal Assistant Computer',appId:'personal-assistant-companion',redirectPort:0,storageDir:join(root,'chatgpt'),credentialEncryption,sendHostId:true,openBrowser});
  const runner=new JobRunner(store,provider,runtime);
  const serverId=createHash('sha256').update(tls.cert).digest('hex').slice(0,32);
  let session=await provider.getSession(), lastError=null, pairingPayload=null, setupOrigin='', apiPort=0;
  const scheduler=new Scheduler(store,runner,{mayRun:(owner,profile)=>session.status==='connected'&&session.sharing&&session.profileId===profile&&!!store.db.prepare('SELECT id FROM devices WHERE id=? AND revoked=0').get(owner)});
  provider.subscribe?.(value=>{session=value;});
  const setupSessions=new Map();
  const listen=(server,port,host)=>new Promise((resolveListen,reject)=>{server.once('error',reject);server.listen(port,host,()=>{server.off('error',reject);resolveListen();});});
  function setupSession(request) {
    const cookie=String(request.headers.cookie??'').split(';').map(x=>x.trim()).find(x=>x.startsWith('pa_setup='))?.slice(9);
    return cookie?setupSessions.get(cookie):null;
  }
  function requireSetup(request) {
    const record=setupSession(request);
    if(!record||record.expires<Date.now()||request.headers.origin!==setupOrigin||request.headers['x-assistant-csrf']!==record.csrf)throw Object.assign(new Error('Reload the computer setup page.'),{status:403});
  }
  async function startJob(job) {
    const connection=await provider.getSession();
    if(!connection.sharing||connection.status!=='connected')throw Object.assign(new Error('Connect ChatGPT on this computer first.'),{status:409});
    if(job.payload.profile_id&&job.payload.profile_id!==connection.profileId)throw Object.assign(new Error('This task belongs to a different ChatGPT connection.'),{status:409});
    if(runner.active.size>=4&&!runner.active.has(job.id))throw Object.assign(new Error('Four tasks are already running on this computer.'),{status:429});
    runner.start(job.id,job.owner);return store.get(job.id,job.owner);
  }
  const api=https.createServer({cert:tls.cert,key:tls.key},async(request,response)=>{
    try {
      const url=new URL(request.url,'https://computer.invalid');
      if(url.pathname==='/v1/info'&&request.method==='GET')return jsonReply(response,200,{version:'1.0.0',server_id:serverId,name:'Personal Assistant Computer'});
      if(url.pathname==='/v1/pair'&&request.method==='POST'){
        if(session.status!=='connected'||!session.sharing)throw new Error('Sign in to ChatGPT on the computer before connecting a phone.');
        const body=await jsonBody(request,4096),device=pairing.redeem(body.pairing_code,body.device_name);
        return jsonReply(response,200,{...device,server_id:serverId,profile_id:session.profileId??null});
      }
      const owner=pairing.authenticate(request.headers.authorization);
      if(url.pathname==='/v1/capabilities'&&request.method==='GET')return jsonReply(response,200,{version:'1.0.0',profile:session,computer_tools:computerTools,computation_ready:await runtime.available(),background_work:'Owned by this computer; phone operations wait for the phone.'});
      if(url.pathname==='/v1/models'&&request.method==='GET')return jsonReply(response,200,{models:await provider.listModels()});
      if(url.pathname==='/v1/metadata'&&request.method==='POST'){
        const body=await jsonBody(request,128*1024),connection=await provider.getSession();
        if(!connection.sharing||connection.status!=='connected'||body.profile_id!==connection.profileId)throw new Error('Reconnect the original ChatGPT account.');
        if(typeof body.body?.model!=='string'||!Array.isArray(body.body.input))throw new Error('Invalid naming request.');
        const result=await provider.streamTurn({body:{...body.body,tools:[],store:false,stream:true},signal:AbortSignal.timeout(25000),onEvent:()=>{}});
        const text=(result.output??[]).filter(item=>item.type==='message').flatMap(item=>item.content??[]).filter(item=>item.type==='output_text').map(item=>item.text??'').join('');
        return jsonReply(response,200,{text:text.slice(0,1000)});
      }
      if(url.pathname==='/v1/schedules'&&request.method==='GET')return jsonReply(response,200,{schedules:scheduler.list(owner)});
      if(url.pathname==='/v1/schedules'&&request.method==='POST')return jsonReply(response,201,scheduler.create(owner,await jsonBody(request,16384)));
      const schedule=url.pathname.match(/^\/v1\/schedules\/([a-zA-Z0-9-]+)$/);
      if(schedule&&request.method==='POST'){const body=await jsonBody(request,4096);return jsonReply(response,200,scheduler.setEnabled(owner,schedule[1],body.enabled));}
      if(url.pathname==='/v1/jobs'&&request.method==='GET')return jsonReply(response,200,{jobs:store.list(owner).map(publicJob)});
      if(url.pathname==='/v1/jobs'&&request.method==='POST'){
        const payload=validateJob(await jsonBody(request,40*1024*1024));
        const connection=await provider.getSession();
        if(!connection.sharing||connection.status!=='connected'||payload.profile_id!==connection.profileId)throw Object.assign(new Error('Reconnect the computer’s ChatGPT account before starting this task.'),{status:409});
        const result=store.create(owner,payload.request_key,payload);
        return jsonReply(response,result.created?201:200,publicJob(result.job));
      }
      const match=url.pathname.match(/^\/v1\/jobs\/([a-zA-Z0-9-]+)(?:\/(.*))?$/);
      if(!match)return jsonReply(response,404,{error:'That action is not available.'});
      const id=match[1],action=match[2]??'',job=store.get(id,owner);
      if(!action&&request.method==='GET')return jsonReply(response,200,publicJob(job));
      if(action==='resume-info'&&request.method==='GET')return jsonReply(response,200,{job:publicJob(job),payload:job.payload});
      if(action==='start'&&request.method==='POST'){await jsonBody(request,4096);return jsonReply(response,200,publicJob(await startJob(job)));}
      if(action==='cancel'&&request.method==='POST'){await jsonBody(request,4096);return jsonReply(response,200,publicJob(runner.cancel(id,owner)));}
      if(action==='events'&&request.method==='GET'){
        const after=Number(url.searchParams.get('after')??0),wait=Math.min(25000,Math.max(0,Number(url.searchParams.get('wait_ms'))||0));
        let events=store.events(id,owner,after);
        if(!events.length&&!terminal.has(job.status)&&wait){
          await new Promise(resolveWait=>{
            let timer;const finish=()=>{clearTimeout(timer);runner.off('event',changed);request.off('close',finish);resolveWait();};
            const changed=jobId=>{if(jobId===id)finish();};
            runner.on('event',changed);request.once('close',finish);timer=setTimeout(finish,wait);
          });
          events=store.events(id,owner,after);
        }
        if(!response.destroyed)return jsonReply(response,200,{job:publicJob(store.get(id,owner)),events});
        return;
      }
      if(action==='files'&&request.method==='POST'){
        if(job.status!=='queued')throw Object.assign(new Error('Inputs must be supplied before the task starts.'),{status:409});
        const body=await jsonBody(request,36*1024*1024);
        if(!safeFileName(body.filename)||typeof body.data_base64!=='string')throw new Error('Provide a named task file.');
        const bytes=Buffer.from(body.data_base64,'base64');if(bytes.length>24*1024*1024)throw new Error('This input file is too large.');
        if(body.id!=null&&!/^[a-zA-Z0-9-]{1,80}$/.test(body.id))throw new Error('Invalid input identifier.');
        const existing=store.files(id,owner),prior=existing.find(file=>file.id===body.id);
        if(prior){
          if(prior.sha!==createHash('sha256').update(bytes).digest('hex')||prior.filename!==body.filename)throw Object.assign(new Error('This file identifier belongs to a different input.'),{status:409});
          return jsonReply(response,200,prior);
        }
        if(existing.length>=20||existing.reduce((sum,file)=>sum+file.bytes,0)+bytes.length>64*1024*1024)throw new Error('Selected task files exceed the input allowance.');
        const saved=store.saveFile(id,{id:body.id,filename:body.filename,role:'input',contains_health_data:body.contains_health_data===true},bytes);
        return jsonReply(response,201,saved);
      }
      if(action==='files'&&request.method==='GET')return jsonReply(response,200,{files:store.files(id,owner)});
      const file=action.match(/^files\/([a-zA-Z0-9-]+)$/);
      if(file&&request.method==='GET'){
        const record=store.file(id,owner,file[1],url.searchParams.has('version')?Number(url.searchParams.get('version')):null);
        response.writeHead(200,{'Content-Type':'application/octet-stream','Content-Length':record.data.length,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Content-Disposition':`attachment; filename*=UTF-8''${encodeURIComponent(record.metadata.filename)}`});response.end(record.data);return;
      }
      const operation=action.match(/^operations\/([a-zA-Z0-9_-]+)\/result$/);
      const operationRead=action.match(/^operations\/([a-zA-Z0-9_-]+)$/);
      if(operationRead&&request.method==='GET')return jsonReply(response,200,store.operation(id,operationRead[1]));
      if(operation&&request.method==='POST'){
        const result=await jsonBody(request,4*1024*1024);
        if(typeof result.succeeded!=='boolean'||!Object.hasOwn(result,'output'))throw new Error('Provide the recorded action outcome.');
        runner.answer(id,owner,operation[1],result);return jsonReply(response,200,{recorded:true});
      }
      return jsonReply(response,404,{error:'That action is not available.'});
    } catch(error){if(!response.headersSent)jsonReply(response,error.status??400,{error:String(error.publicMessage??error.message??'The request could not finish.').slice(0,600)});else response.destroy();}
  });
  api.requestTimeout=70000;api.headersTimeout=10000;
  await listen(api,options.apiPort??48681,options.apiHost??'0.0.0.0');apiPort=api.address().port;

  const setup=http.createServer(async(request,response)=>{
    try {
      if(request.headers.host!==new URL(setupOrigin).host)throw Object.assign(new Error('Unexpected setup address.'),{status:403});
      const url=new URL(request.url,setupOrigin);
      const staticFiles=new Map([['/','index.html'],['/app.js','app.js'],['/styles.css','styles.css']]);
      if(request.method==='GET'&&staticFiles.has(url.pathname)){
        let body=await readFile(join(assets,staticFiles.get(url.pathname)));
        const headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"};
        if(url.pathname==='/'){
          const id=randomBytes(24).toString('base64url'),csrf=randomBytes(24).toString('base64url');
          if(setupSessions.size>30)setupSessions.clear();setupSessions.set(id,{csrf,expires:Date.now()+86400000});
          body=Buffer.from(body.toString().replace('ASSISTANT_CSRF',csrf));headers['Set-Cookie']=`pa_setup=${id}; HttpOnly; SameSite=Strict; Path=/`;
        }
        headers['Content-Type']=url.pathname.endsWith('.js')?'text/javascript':url.pathname.endsWith('.css')?'text/css':'text/html';response.writeHead(200,headers);response.end(body);return;
      }
      if(request.method!=='POST')return jsonReply(response,405,{error:'Use the setup controls.'});
      requireSetup(request);const body=await jsonBody(request,16384);
      if(url.pathname==='/api/status')return jsonReply(response,200,{version:'1.0.0',session,computation_ready:await runtime.available(),addresses:addresses(apiPort),devices:pairing.devices(),jobs:store.list().map(publicJob),error:lastError});
      if(url.pathname==='/api/sign-in'){
        if(runner.active.size)throw new Error('Finish or stop active tasks before changing accounts.');
        lastError=null;provider.signIn().then(value=>{session=value;}).catch(error=>{lastError=String(error.message).slice(0,400);});
        return jsonReply(response,202,{started:true});
      }
      if(url.pathname==='/api/pairing'){
        const permitted=addresses(apiPort).map(item=>item.url);if(!permitted.includes(body.base_url))throw new Error('Choose this computer’s connection address.');
        pairingPayload=pairing.issue({baseURL:body.base_url,fingerprint:tls.fingerprint,serverId});
        return jsonReply(response,200,{payload:pairingPayload,qr:await QRCode.toDataURL(JSON.stringify(pairingPayload),{width:300,margin:2})});
      }
      if(url.pathname==='/api/cancel'){
        const job=store.list().find(job=>job.id===body.job_id);if(!job)throw new Error('Task not found.');runner.cancel(job.id,job.owner);return jsonReply(response,200,{stopped:true});
      }
      if(url.pathname==='/api/revoke'){
        pairing.revoke(body.device_id);scheduler.stopOwner(body.device_id);for(const job of store.list(body.device_id))if(!terminal.has(job.status))runner.cancel(job.id,job.owner);
        return jsonReply(response,200,{disconnected:true});
      }
      return jsonReply(response,404,{error:'That setup action is not available.'});
    }catch(error){if(!response.headersSent)jsonReply(response,error.status??400,{error:String(error.message??'Setup could not finish.').slice(0,500)});else response.destroy();}
  });
  await listen(setup,options.setupPort??48680,'127.0.0.1');setupOrigin=`http://127.0.0.1:${setup.address().port}`;
  for(const job of store.list())if(['running','waiting_for_phone','waiting_for_input'].includes(job.status))store.status(job.id,'interrupted','The computer restarted. Saved work is ready to continue.');
  const scheduleTimer=setInterval(()=>scheduler.tick().catch(()=>{lastError='A scheduled task needs attention. Its saved record is kept.';}),15000);scheduleTimer.unref();
  let powerLease;
  if(options.keepAwake!==false&&process.platform==='win32'){
    powerLease=spawn(join(process.env.SystemRoot??'C:\\Windows','System32','WindowsPowerShell','v1.0','powershell.exe'),['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',fileURLToPath(new URL('../scripts/keep-awake.ps1',import.meta.url))],{windowsHide:true,stdio:['pipe','ignore','ignore']});powerLease.on('error',()=>{lastError='Keep this computer awake manually; the app could not obtain a power lease.';});powerLease.on('exit',code=>{if(code)lastError='Keep this computer awake manually; its power lease could not start.';});
  }
  return {setupURL:setupOrigin,apiPort,store,runner,pairing,provider,tls,
    close:async()=>{clearInterval(scheduleTimer);powerLease?.stdin.end();for(const job of store.list())if(runner.active.has(job.id))runner.interrupt(job.id);await Promise.all([...runner.active.values()].map(value=>value.promise));await Promise.all([new Promise(r=>setup.close(r)),new Promise(r=>api.close(r))]);store.close();}};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{
    const local=process.argv.includes('--local-test');
    const host=await startCompanion({apiHost:local?'127.0.0.1':'0.0.0.0'});
    console.log('Personal Assistant Computer is ready at '+host.setupURL);
    if(!process.argv.includes('--no-open'))openBrowser(host.setupURL);
    process.on('SIGINT',()=>{host.close().then(()=>process.exit(0));});
    process.on('SIGTERM',()=>{host.close().then(()=>process.exit(0));});
  }catch(error){
    const logs=join(process.env.LOCALAPPDATA??'.','PersonalAssistantCompanion','logs');await mkdir(logs,{recursive:true});
    await appendFile(join(logs,'startup.log'),new Date().toISOString()+' Startup failed: '+String(error.message).slice(0,600)+'\n');
    process.exitCode=1;
  }
}
