import {chromium} from 'playwright-core';
import {mkdtemp,rm,mkdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {randomBytes} from 'node:crypto';
import assert from 'node:assert/strict';
import {startCompanion} from '../src/server.mjs';
import {Vault} from '../src/vault.mjs';

const root=await mkdtemp(join(tmpdir(),'assistant-bridge-ui-')),sent=[];
const service=await startCompanion({root,apiHost:'127.0.0.1',apiPort:0,setupPort:0,keepAwake:false,vault:new Vault(randomBytes(32)),
  provider:{getSession:async()=>({status:'connected',sharing:true,profileId:'fixture'}),streamTurn:async()=>{throw new Error('No model calls in UI verification');}},
  runtime:{definitions:[],available:async()=>true,supports:()=>false},
  bridgeOptions:{request:async(path,options)=>{sent.push({path,method:options.method});return path==='/auth/me'?{quota_period_month:202610,notifications_used:0,live_activity_updates_used:0,integration_key:{permissions:{activities:'manage',notifications:'send'}}}:{delivery:'all'};}}});
const code=service.pairing.issue({baseURL:`https://127.0.0.1:${service.apiPort}`,fingerprint:service.tls.fingerprint,serverId:'fixture'});
service.pairing.redeem(code.pairing_code,'Synthetic iPhone');
let browser;
try{
  browser=await chromium.launch({headless:true,executablePath:'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'});
  const page=await browser.newPage({viewport:{width:1180,height:900}});
  await page.goto(service.setupURL);
  await page.locator('#bridge-key').fill('hlk_'+'a'.repeat(32));
  await page.getByRole('button',{name:'Connect PushWard',exact:true}).click();
  await page.getByText('Connected · brief task updates go to PushWard.').waitFor();
  assert.equal(await page.locator('#bridge-key').inputValue(),'');
  await page.getByRole('button',{name:'Send a connection test'}).click();
  await page.getByText('Check your iPhone for the Live Activity and alert',{exact:false}).waitFor();
  assert.ok(sent.some(value=>value.path==='/notifications'));
  await page.getByRole('button',{name:'Clear test activity'}).click();
  await page.getByText('The connection-test activity was cleared.').waitFor();
  assert.ok(sent.some(value=>value.path==='/activities/pa-connection-test'&&value.method==='DELETE'));
  const directory=resolve('../.build');await mkdir(directory,{recursive:true});
  await page.locator('#bridge-status').scrollIntoViewIfNeeded();
  await page.screenshot({path:join(directory,'pushward-controls.png')});
  console.log('PushWard setup, hidden key clearing, quota display and test controls passed against synthetic delivery. No live push or model call.');
}finally{await browser?.close();await service.close();await rm(root,{recursive:true,force:true});}
