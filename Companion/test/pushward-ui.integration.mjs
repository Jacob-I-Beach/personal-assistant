import {chromium} from 'playwright-core';
import {mkdtemp,rm,mkdir,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {randomBytes} from 'node:crypto';
import assert from 'node:assert/strict';
import {startCompanion} from '../src/server.mjs';
import {Vault} from '../src/vault.mjs';

const root=await mkdtemp(join(tmpdir(),'assistant-bridge-ui-')),sent=[];let catalogFailure=false;
const service=await startCompanion({root,apiHost:'127.0.0.1',apiPort:0,setupPort:0,keepAwake:false,vault:new Vault(randomBytes(32)),
  provider:{getSession:async()=>({status:'connected',sharing:true,profileId:'fixture'}),listModels:async()=>{if(catalogFailure)throw Object.assign(new Error('Synthetic provider failure'),{status:520});return[{slug:'synthetic',displayName:'Synthetic'}];},streamTurn:async()=>{throw new Error('No model calls in UI verification');}},
  runtime:{definitions:[],available:async()=>true,supports:()=>false},
  bridgeOptions:{request:async(path,options)=>{sent.push({path,method:options.method});return path==='/auth/me'?{quota_period_month:202610,notifications_used:0,live_activity_updates_used:0,integration_key:{permissions:{activities:'manage',notifications:'send'}}}:{delivery:'all'};}}});
const code=service.pairing.issue({baseURL:`https://127.0.0.1:${service.apiPort}`,fingerprint:service.tls.fingerprint,serverId:'fixture'});
service.pairing.redeem(code.pairing_code,'Synthetic iPhone');
let browser; const reviewAbort=new AbortController(); let reviewCompletion;
try{
  browser=await chromium.launch({headless:true,executablePath:'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'});
  const page=await browser.newPage({viewport:{width:1180,height:900}});
  await page.route('**/api/status',async route=>{
    const response=await route.fetch(),state=await response.json();
    state.addresses=[{label:'Synthetic private connection',url:'https://100.64.0.2:48681'}];
    await route.fulfill({response,json:state});
  });
  await page.goto(service.setupURL);
  await page.locator('body.returning').waitFor();
  const packageVersion=JSON.parse(await readFile(new URL('../package.json',import.meta.url),'utf8')).version;
  assert.ok((await page.locator('footer').innerText()).includes(packageVersion));
  assert.equal(await page.locator('#connections-panel').getAttribute('open'),null);
  assert.equal(await page.locator('.work').evaluate((work)=>work.getBoundingClientRect().top<document.querySelector('#connections-panel').getBoundingClientRect().top),true);
  await page.locator('#connections-panel > summary').click();
  await page.getByText('Ready for Python, spreadsheets, documents and page inspection.').waitFor();
  assert.equal(await page.locator('#bridge-form').isVisible(),false);
  assert.equal(await page.locator('#bridge-test').isVisible(),false);
  await page.getByText('Advanced · Notifications & Live Activities',{exact:true}).click();
  await page.getByText('Remote alerts and Island updates are deferred',{exact:false}).waitFor();
  assert.equal(sent.length,0,'deferred setup must not contact PushWard');
  const readiness=await page.evaluate(async()=>{
    const csrf=document.querySelector('meta[name="csrf-token"]').content;
    return (await fetch('/api/check-connection',{method:'POST',headers:{'Content-Type':'application/json','X-Assistant-CSRF':csrf},body:JSON.stringify({model:'synthetic'})})).json();
  });
  assert.equal(readiness.selected_model_available,true);
  catalogFailure=true;
  await page.getByRole('button',{name:'Check model connection'}).click();
  await page.getByText('Saved model list · ChatGPT model discovery returned HTTP 520.',{exact:false}).waitFor();
  assert.equal(await page.getByRole('button',{name:'Check model connection'}).isEnabled(),true);
  assert.ok((await page.locator('#account').innerText()).startsWith('Signed in'));
  const finished=service.store.create('fixture-device','ui-completed',{title:'Synthetic completed work',conversation_id:'fixture-chat',turn_id:'fixture-turn',body:{model:'synthetic'}}).job;
  service.store.append(finished.id,{type:'continuation',output:[{id:'answer-1',type:'message',role:'assistant',content:[{type:'output_text',text:'## Saved result\nThe synthetic report is ready.'}]}]});
  service.store.saveFile(finished.id,{filename:'result.md',role:'artifact'},Buffer.from('Synthetic report, preserved.'));
  service.store.status(finished.id,'completed','Ready');
  const reviewJob=service.store.create('fixture-device','ui-review',{title:'Synthetic review task',conversation_id:'fixture-chat',turn_id:'fixture-review-turn',body:{model:'synthetic'}}).job;
  const original={id:'review-action',name:'synthetic_action',arguments:{}};
  service.store.beginOperation(reviewJob.id,original.id,original,'computer');
  reviewCompletion=service.runner.reviewComputer(reviewJob,original,{title:'Review a synthetic action',detail:'No real-world action will be performed.'},reviewAbort.signal).then(result=>{service.store.status(reviewJob.id,'completed','Review recorded');return result;});
  await page.reload();
  const reviewRow=page.locator('.job').filter({hasText:'Synthetic review task'});await reviewRow.getByRole('button',{name:'Open task'}).click();
  await page.getByRole('heading',{name:'Review a synthetic action'}).waitFor();
  await page.locator('#task-dialog').getByRole('button',{name:'Cancel',exact:true}).click();
  const reviewed=await reviewCompletion;assert.equal(reviewed.output.status,'cancelled');
  await page.locator('#close-task').click();
  await page.locator('.job').filter({hasText:'Synthetic completed work'}).getByRole('button',{name:'Open task'}).click();
  await page.getByRole('heading',{name:'Saved result'}).waitFor();
  const downloadPromise=page.waitForEvent('download');await page.getByRole('button',{name:'Download result.md'}).click();
  const download=await downloadPromise;assert.equal((await readFile(await download.path(),'utf8')),'Synthetic report, preserved.');
  await page.locator('#close-task').click();
  await page.reload();await page.locator('.job').filter({hasText:'Synthetic completed work'}).waitFor();
  assert.equal(service.store.get(finished.id,'fixture-device').status,'completed','closing/reopening the page cannot stop completed work');
  const directory=resolve('../.build');await mkdir(directory,{recursive:true});
  await page.locator('#push-status').scrollIntoViewIfNeeded();
  await page.screenshot({path:join(directory,'deferred-delivery-controls.png')});
  await page.locator('#account').scrollIntoViewIfNeeded();await page.screenshot({path:join(directory,'catalog-unavailable-controls.png')});
  await page.emulateMedia({colorScheme:'light',reducedMotion:'reduce'});
  await page.setViewportSize({width:420,height:880});
  await page.locator('#connections-panel > summary').click();await page.evaluate(()=>scrollTo(0,0));
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'narrow layout must not overflow');
  await page.screenshot({path:join(directory,'companion-returning-light-120.png')});
  await page.emulateMedia({colorScheme:'dark'});await page.setViewportSize({width:1180,height:900});
  await page.screenshot({path:join(directory,'companion-returning-dark-120.png')});
  console.log('Deferred delivery controls and absence of PushWard calls verified in Edge. No live push or model call.');
}finally{reviewAbort.abort(new Error('Synthetic UI finished'));await reviewCompletion?.catch(()=>{});await browser?.close();await service.close();await rm(root,{recursive:true,force:true});}
