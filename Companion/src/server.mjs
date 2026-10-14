import http from 'node:http';
import https from 'node:https';
import {readFile,mkdir,appendFile} from 'node:fs/promises';
import {dirname,join,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {networkInterfaces} from 'node:os';
import {randomBytes,createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import QRCode from 'qrcode';
import {createChatGPT} from '@siwc/local';
import {Vault,credentialEncryption} from './vault.mjs';
import {JobStore} from './job-store.mjs';
import {JobRunner} from './job-runner.mjs';
import {ComputeRuntime} from './compute-runtime.mjs';
import {Pairing} from './pairing.mjs';
import {certificate} from './certificate.mjs';
import {jsonBody,jsonReply,validateJob} from './http-helpers.mjs';
import {Scheduler} from './scheduler.mjs';
import {ToolSessions} from './tool-sessions.mjs';
import {HostRuntime} from './host-runtime.mjs';
import {PushDelivery} from './push-delivery.mjs';
import {PushWardBridge} from './pushward.mjs';
import {computerDataRoot,resolveComputerDataRoot} from './data-location.mjs';
import {ModelCatalog} from './model-catalog.mjs';
import {ServiceReadiness} from './service-readiness.mjs';

const version=JSON.parse(await readFile(new URL('../package.json',import.meta.url),'utf8')).version;
if(typeof version!=='string'||!/^\d+\.\d+\.\d+$/.test(version))throw new Error('Invalid companion package version.');
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
  const root=resolve(options.root??await resolveComputerDataRoot());
  await mkdir(root,{recursive:true});
  const vault=options.vault??await Vault.open(root), tls=options.tls??await certificate(root);
  const store=new JobStore(join(root,'work.db'),vault),pairing=new Pairing(store,vault);
  const runtime=options.runtime??new HostRuntime({root:join(root,'workspaces'),store,compute:new ComputeRuntime({root:join(root,'temporary-executions'),store})});
  const provider=options.provider??createChatGPT({appName:'Personal Assistant Computer',appId:'personal-assistant-companion',redirectPort:0,storageDir:join(root,'chatgpt'),credentialEncryption,sendHostId:true,openBrowser});
  const mayRun=job=>!!store.db.prepare('SELECT id FROM devices WHERE id=? AND revoked=0').get(job.owner);
  const toolSessions=new ToolSessions(store,runtime,{mayRun});
  const modelCatalog=new ModelCatalog(store,provider);
  const computation=new ServiceReadiness(signal=>runtime.available(signal));
  const runner=new JobRunner(store,provider,runtime,(job,signal)=>toolSessions.prepareHandoff(job,signal),{mayRun});
  if(runtime instanceof HostRuntime)runtime.approve=(job,call,review,signal)=>runner.reviewComputer(job,call,review,signal);
  const push=new PushDelivery(store,options.pushOptions);
  runner.on('event',(id,event)=>{const owner=store.db.prepare('SELECT owner FROM jobs WHERE id=?').get(id)?.owner;if(!bridge.enabled(owner))push.queue(id,event);});
  runner.on('settled',id=>{const job=store.db.prepare('SELECT status FROM jobs WHERE id=?').get(id);if(job&&['completed','cancelled'].includes(job.status))Promise.resolve(runtime.close?.(id)).catch(()=>{});});
  const serverId=createHash('sha256').update(tls.cert).digest('hex').slice(0,32);
  const bridge=new PushWardBridge(store,{...options.bridgeOptions,serverID:serverId});
  // Remote delivery is deferred by the user's choice. Retain saved tasks and
  // the future native APNs setup, but retire a previously enabled bridge.
  if(bridge.config()?.enabled)await bridge.disconnect();
  runner.on('event',(id,event)=>bridge.queue(id,event));
  let session=await provider.getSession(), lastError=null, pairingPayload=null, setupOrigin='', apiPort=0,closing=false,closeService;
  const scheduler=new Scheduler(store,runner,{mayRun:(owner,profile)=>!closing&&session.status==='connected'&&session.sharing&&session.profileId===profile&&!!store.db.prepare('SELECT id FROM devices WHERE id=? AND revoked=0').get(owner)});
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
    if(!mayRun(job))throw Object.assign(new Error('This device is no longer connected.'),{status:403});
    const files=new Set(store.files(job.id,job.owner).map(file=>file.id));
    if(!(job.payload.expected_file_ids??[]).every(id=>files.has(id)))throw Object.assign(new Error('The selected input files are still uploading.'),{status:409});
    const connection=await provider.getSession();
    if(!connection.sharing||connection.status!=='connected')throw Object.assign(new Error('Connect ChatGPT on this computer first.'),{status:409});
    if(job.payload.profile_id&&job.payload.profile_id!==connection.profileId)throw Object.assign(new Error('This task belongs to a different ChatGPT connection.'),{status:409});
    if(runner.active.size>=4&&!runner.active.has(job.id))throw Object.assign(new Error('Four tasks are already running on this computer.'),{status:429});
    runner.start(job.id,job.owner);return store.get(job.id,job.owner);
  }
  async function startWhenReady(job){
    if(job.status!=='queued'||!job.payload.start_when_ready)return;
    const supplied=new Set(store.files(job.id,job.owner).map(file=>file.id));
    if(!(job.payload.expected_file_ids??[]).every(id=>supplied.has(id)))return;
    try{await startJob(job);}catch(error){if(error.status!==429)lastError='A saved request is waiting for its ChatGPT connection.';}
  }
  const api=https.createServer({cert:tls.cert,key:tls.key},async(request,response)=>{
    try {
      const url=new URL(request.url,'https://computer.invalid');
      if(url.pathname==='/v1/info'&&request.method==='GET')return jsonReply(response,200,{version,server_id:serverId,name:'Personal Assistant Computer'});
      if(url.pathname==='/v1/pair'&&request.method==='POST'){
        if(session.status!=='connected'||!session.sharing)throw new Error('Sign in to ChatGPT on the computer before connecting a phone.');
        const body=await jsonBody(request,4096),device=pairing.redeem(body.pairing_code,body.device_name);
        return jsonReply(response,200,{...device,server_id:serverId,profile_id:session.profileId??null});
      }
      const owner=pairing.authenticate(request.headers.authorization);
      if(url.pathname==='/v1/tool-sessions'&&request.method==='POST'){
        const job=toolSessions.create(owner,await jsonBody(request,8192));
        return jsonReply(response,200,{id:job.id});
      }
      if(url.pathname==='/v1/cancel-request'&&request.method==='POST'){
        const body=await jsonBody(request,4096),job=store.cancelRequest(owner,body.request_key);
        if(job)runner.cancel(job.id,owner);
        return jsonReply(response,200,{status:job?.status==='completed'?'completed':'cancelled',notice:'Stop recorded for this request. Any already-started action retains its actual receipt.'});
      }
      if(url.pathname==='/v1/capabilities'&&request.method==='GET'){
        const readiness=computation.snapshot();
        return jsonReply(response,200,{version,profile:session,computer_tools:runtime.definitions,computation_ready:readiness.available,computation:readiness,push:push.status(),presentation:{provider:bridge.enabled(owner)?'pushward':'native'},background_work:'Owned by this computer from Send; phone operations wait for the phone.'});
      }
      if(url.pathname==='/v1/models'&&request.method==='GET'){
        const catalog=await modelCatalog.load({force:url.searchParams.get('refresh')==='1'});
        return jsonReply(response,200,{...catalog,models:catalog.models.map(model=>({...model,display_name:model.displayName,visibility:'list',context_window:model.contextWindow,max_context_window:model.maximumContextWindow,supported_reasoning_levels:model.reasoningEfforts}))});
      }
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
      if(url.pathname==='/v1/jobs'&&request.method==='GET')return jsonReply(response,200,{jobs:store.list(owner).filter(job=>!job.payload.execution_only).map(publicJob)});
      if(url.pathname==='/v1/jobs'&&request.method==='POST'){
        const payload=validateJob(await jsonBody(request,40*1024*1024));
        const connection=await provider.getSession();
        if(!connection.sharing||connection.status!=='connected'||payload.profile_id!==connection.profileId)throw Object.assign(new Error('Reconnect the computer’s ChatGPT account before starting this task.'),{status:409});
        const source=payload.source_tool_session_id?store.get(payload.source_tool_session_id,owner):null;
        if(source&&(!source.payload.execution_only||source.payload.turn_id!==payload.turn_id||source.payload.conversation_id!==payload.conversation_id))throw new Error('The tool workspace belongs to another task.');
        const result=store.create(owner,payload.request_key,payload);
        if(source){
          const copied=new Set(store.files(result.job.id,owner).map(file=>file.id));
          for(const metadata of store.files(source.id,owner)){
            if(copied.has(metadata.id))continue;
            const file=store.file(source.id,owner,metadata.id);
            store.saveFile(result.job.id,{...metadata,version:undefined,sha:undefined},file.data);
          }
        }
        queueMicrotask(()=>startWhenReady(store.get(result.job.id,owner)).catch(()=>{}));
        return jsonReply(response,result.created?201:200,publicJob(result.job));
      }
      const match=url.pathname.match(/^\/v1\/jobs\/([a-zA-Z0-9-]+)(?:\/(.*))?$/);
      if(!match)return jsonReply(response,404,{error:'That action is not available.'});
      const id=match[1],action=match[2]??'',job=store.metadata(id,owner);
      if(!action&&request.method==='GET')return jsonReply(response,200,{...publicJob(job),presentation_provider:bridge.enabled(owner)?'pushward':'native'});
      if(action==='push'&&request.method==='POST')return jsonReply(response,200,push.register(owner,id,await jsonBody(request,8192)));
      if(action==='presentation/viewed'&&request.method==='POST'){await jsonBody(request,1024);await bridge.viewed(owner,id);return jsonReply(response,200,{recorded:true});}
      if(action==='resume-info'&&request.method==='GET')return jsonReply(response,200,{job:publicJob(job),payload:store.get(id,owner).payload});
      if(action==='start'&&request.method==='POST'){const body=await jsonBody(request,4096);if(store.get(id,owner).payload.execution_only)throw new Error('This workspace is for tools only.');if(body.context_text_bytes!=null)store.contextBudget(id,owner,body.context_text_bytes);return jsonReply(response,200,publicJob(await startJob(store.get(id,owner))));}
      if(action==='execute-tool'&&request.method==='POST')return jsonReply(response,200,toolSessions.start(id,owner,await jsonBody(request,256*1024)));
      if(action==='cancel'&&request.method==='POST'){await jsonBody(request,4096);return jsonReply(response,200,publicJob(store.get(id,owner).payload.execution_only?toolSessions.cancel(id,owner):runner.cancel(id,owner)));}
      if(action==='events'&&request.method==='GET'){
        const after=Number(url.searchParams.get('after')??0),wait=Math.min(25000,Math.max(0,Number(url.searchParams.get('wait_ms'))||0));
        let events=store.events(id,owner,after);
        if(!events.length&&!terminal.has(job.status)&&wait){
          await new Promise(resolveWait=>{
            let timer;const finish=()=>{clearTimeout(timer);runner.off('event',changed);response.off('close',finish);resolveWait();};
            const changed=jobId=>{if(jobId===id)finish();};
            runner.on('event',changed);response.once('close',finish);timer=setTimeout(finish,wait);
          });
          events=store.events(id,owner,after);
        }
        if(!response.destroyed)return jsonReply(response,200,{job:publicJob(store.metadata(id,owner)),events});
        return;
      }
      if(action==='files'&&request.method==='POST'){
        if(!['queued','waiting_for_phone'].includes(job.status))throw Object.assign(new Error('Supply inputs before the task starts or through its current phone file request.'),{status:409});
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
        queueMicrotask(()=>startWhenReady(store.get(id,owner)).catch(()=>{}));
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
      const staticFiles=new Map([['/','index.html'],['/app.js','app.js'],['/styles.css','styles.css'],['/workspace.css','workspace.css'],['/vendor/marked.js','../node_modules/marked/lib/marked.umd.js'],['/vendor/purify.js','../node_modules/dompurify/dist/purify.min.js']]);
      if(request.method==='GET'&&staticFiles.has(url.pathname)){
        let body=await readFile(join(assets,staticFiles.get(url.pathname)));
        const headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"};
        if(url.pathname==='/'){
          const id=randomBytes(24).toString('base64url'),csrf=randomBytes(24).toString('base64url');
          if(setupSessions.size>30)setupSessions.clear();setupSessions.set(id,{csrf,expires:Date.now()+86400000});
          body=Buffer.from(body.toString().replace('ASSISTANT_CSRF',csrf).replace('ASSISTANT_VERSION',version));headers['Set-Cookie']=`pa_setup=${id}; HttpOnly; SameSite=Strict; Path=/`;
        }
        headers['Content-Type']=url.pathname.endsWith('.js')?'text/javascript':url.pathname.endsWith('.css')?'text/css':'text/html';response.writeHead(200,headers);response.end(body);return;
      }
      if(request.method!=='POST')return jsonReply(response,405,{error:'Use the setup controls.'});
      requireSetup(request);const body=await jsonBody(request,16384);
      if(url.pathname==='/api/status'){
        const readiness=computation.snapshot();
        return jsonReply(response,200,{version,active_work_count:runner.active.size+toolSessions.active.size,package_path:fileURLToPath(new URL('../',import.meta.url)),data_path:root,session,model_catalog:modelCatalog.snapshot(session.profileId).catalog,computation_ready:readiness.available,computation:readiness,push:push.status(),pushward:bridge.status(),addresses:addresses(apiPort),devices:pairing.devices(),jobs:store.list().filter(job=>!job.payload.execution_only).map(publicJob),error:lastError});
      }
      if(url.pathname==='/api/check-connection'){
        const connection=await provider.getSession();
        if(connection.status!=='connected'||!connection.sharing)return jsonReply(response,200,{connected:false,sharing:connection.sharing===true});
        const result=await modelCatalog.load({force:true}),models=result.models;
        return jsonReply(response,200,{connected:true,sharing:true,catalog:result.catalog,model_count:models.length,selected_model_available:result.catalog.state==='ready'&&typeof body.model==='string'?models.some(model=>model.slug===body.model):null,scope:'Account and model discovery only; no inference request was sent.'});
      }
      if(url.pathname==='/api/push-configure'){push.configure(body);return jsonReply(response,200,push.status());}
      if(['/api/pushward-configure','/api/pushward-test'].includes(url.pathname))throw Object.assign(new Error('PushWard delivery is deferred. Native remote notifications can be configured after Apple Developer setup.'),{status:409});
      if(url.pathname==='/api/pushward-clear-test')return jsonReply(response,200,await bridge.clearTest());
      if(url.pathname==='/api/pushward-refresh')return jsonReply(response,200,await bridge.refreshQuota());
      if(url.pathname==='/api/pushward-disconnect')return jsonReply(response,200,await bridge.disconnect());
      if(url.pathname==='/api/task'){
        const entry=store.controlled(body.job_id);
        return jsonReply(response,200,{job:publicJob(entry),events:store.events(entry.id,entry.owner,Number(body.after)||0),files:store.files(entry.id,entry.owner)});
      }
      if(url.pathname==='/api/file'){
        const job=store.controlled(body.job_id);
        const file=store.file(job.id,job.owner,body.file_id);return jsonReply(response,200,{filename:file.metadata.filename,data_base64:file.data.toString('base64')});
      }
      if(url.pathname==='/api/review'){
        const job=store.controlled(body.job_id);
        const operation=store.operation(job.id,body.operation_id);
        if(operation.request.name!=='review_computer_action'||operation.status!=='waiting_for_phone'||typeof body.approved!=='boolean')throw new Error('This review is no longer available.');
        runner.answer(job.id,job.owner,body.operation_id,{callID:body.operation_id,name:'review_computer_action',succeeded:true,output:{status:body.approved?'approved':'cancelled'},completedAt:new Date().toISOString()});return jsonReply(response,200,{recorded:true});
      }
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
        const job=store.controlled(body.job_id);runner.cancel(job.id,job.owner);return jsonReply(response,200,{stopped:true});
      }
      if(url.pathname==='/api/revoke'){
        pairing.revoke(body.device_id);scheduler.stopOwner(body.device_id);for(const job of store.incomplete(body.device_id)){if(job.payload.execution_only)toolSessions.cancel(job.id,job.owner);else runner.cancel(job.id,job.owner);}
        return jsonReply(response,200,{disconnected:true});
      }
      if(url.pathname==='/api/quit'){
        jsonReply(response,202,{stopping:true});setTimeout(()=>closeService?.().then(()=>options.onQuit?.()),150);return;
      }
      return jsonReply(response,404,{error:'That setup action is not available.'});
    }catch(error){if(!response.headersSent)jsonReply(response,error.status??400,{error:String(error.message??'Setup could not finish.').slice(0,500)});else response.destroy();}
  });
  await listen(setup,options.setupPort??48680,'127.0.0.1');setupOrigin=`http://127.0.0.1:${setup.address().port}`;
  const recover=store.incomplete().filter(job=>!job.payload.execution_only&&job.status!=='queued');
  let recoveryCursor=0;
  for(const job of recover)store.status(job.id,'interrupted','Reconnecting the saved task after the computer restarted.');
  async function recoverWork(){
    if(closing)return;
    for(const entry of recover.splice(0)){
      const device=store.db.prepare('SELECT revoked FROM devices WHERE id=?').get(entry.owner);
      if(!device||device.revoked)continue;
      try{await startJob(store.get(entry.id,entry.owner));}catch{recover.push(entry);}
    }
    const page=store.queued(recoveryCursor);
    for(const entry of page){
      if(closing||runner.active.size>=4)return;
      recoveryCursor=entry.queueCursor;
      if(!mayRun(entry)){if(entry.payload.execution_only)toolSessions.cancel(entry.id,entry.owner);else runner.cancel(entry.id,entry.owner);continue;}
      if(!entry.payload.execution_only)await startWhenReady(store.get(entry.id,entry.owner));
    }
    if(page.length<100)recoveryCursor=0;
  }
  await recoverWork();
  const scheduleTimer=setInterval(()=>Promise.all([scheduler.tick(),recoverWork()]).catch(()=>{lastError='A saved task needs attention. Its record is kept.';}),15000);scheduleTimer.unref();
  let powerLease;
  if(options.keepAwake!==false&&process.platform==='win32'){
    powerLease=spawn(join(process.env.SystemRoot??'C:\\Windows','System32','WindowsPowerShell','v1.0','powershell.exe'),['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',fileURLToPath(new URL('../scripts/keep-awake.ps1',import.meta.url))],{windowsHide:true,stdio:['pipe','ignore','ignore']});powerLease.on('error',()=>{lastError='Keep this computer awake manually; the app could not obtain a power lease.';});powerLease.on('exit',code=>{if(code)lastError='Keep this computer awake manually; its power lease could not start.';});
  }
  let closePromise;
  closeService=()=>closePromise??=(async()=>{
      closing=true;computation.close();clearInterval(scheduleTimer);push.close();await bridge.close();scheduler.stopped=true;powerLease?.stdin.end();
    while(scheduler.busy)await new Promise(resolveWait=>setTimeout(resolveWait,20));
    for(const job of store.incomplete())if(runner.active.has(job.id))runner.interrupt(job.id);
    await Promise.all([...runner.active.values()].map(value=>value.promise));
    await toolSessions.close();
    await runtime.close?.();
    await Promise.all([new Promise(r=>setup.close(r)),new Promise(r=>api.close(r))]);store.close();
  })();
  bridge.wake();
  return {setupURL:setupOrigin,apiPort,store,runner,pairing,provider,tls,push,bridge,close:closeService};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  try{
    const local=process.argv.includes('--local-test');
    const host=await startCompanion({apiHost:local?'127.0.0.1':'0.0.0.0',onQuit:()=>process.exit(0)});
    console.log('Personal Assistant Computer is ready at '+host.setupURL);
    if(!process.argv.includes('--no-open'))openBrowser(host.setupURL);
    process.on('SIGINT',()=>{host.close().then(()=>process.exit(0));});
    process.on('SIGTERM',()=>{host.close().then(()=>process.exit(0));});
  }catch(error){
    const logs=join(dirname(computerDataRoot()),'logs');await mkdir(logs,{recursive:true});
    await appendFile(join(logs,'startup.log'),new Date().toISOString()+' Startup failed: '+String(error.message).slice(0,600)+'\n');
    process.exit(1);
  }
}
