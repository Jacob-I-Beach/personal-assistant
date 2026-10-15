const byId=id=>document.getElementById(id),csrf=document.querySelector('meta[name="csrf-token"]').content;
async function api(path,body={}){const response=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json','X-Assistant-CSRF':csrf},body:JSON.stringify(body)});const value=await response.json();if(!response.ok)throw new Error(value.error??'The request could not finish.');return value;}
function notice(error){byId('notice').textContent=error?.message??'';}
const labels={queued:'Waiting to start',running:'Working',retrying:'Reconnecting automatically',waiting_for_phone:'Needs your iPhone',waiting_for_input:'Needs your answer',completed:'Ready',failed:'Needs attention',cancelled:'Stopped',interrupted:'Saved task reconnecting'};
function action(text,handler){const button=document.createElement('button');button.textContent=text;button.addEventListener('click',()=>handler().catch(notice));return button;}
let addressesKey='',jobsKey='',bridgeDevicesKey='',checkingModels=false,layoutInitialized=false;
async function refresh(){
  try{const state=await api('/api/status');const session=state.session;
    byId('account').textContent=session.status==='connected'?(session.sharing?'Signed in · '+(session.identity?.name??session.profileLabel??'ChatGPT plan'):'Signed in; plan sharing needs authorization'):'Connect the ChatGPT account you want this computer to use.';
    const catalog=state.model_catalog;
    const returning=state.devices.length>0||state.jobs.length>0;
    document.body.classList.toggle('returning',returning);
    if(!layoutInitialized){byId('connections-panel').open=!returning;layoutInitialized=true;}
    byId('connection-summary').textContent=(session.status==='connected'?'Account signed in':'Account not connected')+' · '+(catalog?.state==='ready'?'Models available':catalog?.state==='stale'?'Models need a refresh':'Models not verified')+' · '+(state.computation_ready?'Computation ready':state.computation?.state==='checking'?'Computation checking':'Computation unavailable');

    if(!checkingModels)byId('catalog-status').textContent=catalog?.state==='ready'?'Model list available.':catalog?.state==='stale'?'Saved model list · '+(catalog.error??'Refresh to check current availability.'):(catalog?.error??'Model availability has not been checked.');
    byId('check-models').disabled=checkingModels||session.status!=='connected'||!session.sharing;
    byId('connect').textContent=session.status==='connecting'?'Waiting for browser authorization…':session.status==='connected'?'Reconnect ChatGPT':'Continue with ChatGPT';byId('connect').disabled=session.status==='connecting';
    byId('compute').textContent=state.computation?.state==='checking'?'Checking the computation service…':state.computation_ready?'Ready for Python, spreadsheets, documents and page inspection.':'The computation service is not ready yet. Other connected tools remain available; start Docker Desktop for Python and document work.';
    byId('push-status').textContent=state.push?.configured?(state.push.last_error??'Configured · Updates travel through Apple’s push service.'):'Not provisioned yet · Tasks can keep working; remote phone updates need Apple Developer setup.';
    const key=JSON.stringify(state.addresses);if(key!==addressesKey){addressesKey=key;byId('address').replaceChildren(...state.addresses.map(item=>{const option=document.createElement('option');option.value=item.url;option.textContent=item.label+' · '+new URL(item.url).hostname;return option;}));}byId('pair').disabled=!state.addresses.length||session.status!=='connected'||!session.sharing;
    const updatedJobs=JSON.stringify(state.jobs.map(job=>[job.id,job.status,job.title]));
    if(updatedJobs!==jobsKey){jobsKey=updatedJobs;
    byId('count').textContent=state.jobs.length?state.jobs.length+' task'+(state.jobs.length===1?'':'s'):'';byId('jobs').replaceChildren();
    if(!state.jobs.length){const empty=document.createElement('p');empty.className='empty';empty.textContent='Tasks from your iPhone will appear here.';byId('jobs').append(empty);}
    for(const job of state.jobs){const row=document.createElement('div');row.className='job';const content=document.createElement('div'),title=document.createElement('h3'),detail=document.createElement('p');title.textContent=job.title;detail.textContent=(labels[job.status]??job.status)+' · '+job.model;content.append(title,detail);row.append(content,action('Open task',()=>openTask(job)));if(!['completed','cancelled','failed','interrupted'].includes(job.status))row.append(action('Stop task',()=>api('/api/cancel',{job_id:job.id}).then(refresh)));byId('jobs').append(row);}}
    byId('devices').replaceChildren(...state.devices.map(device=>{const row=document.createElement('div');row.className='device';const label=document.createElement('span');label.textContent=device.name;row.append(label,action('Disconnect',()=>api('/api/revoke',{device_id:device.id}).then(refresh)));return row;}));
    const bridge=state.pushward??{};
    byId('bridge-status').textContent=bridge.enabled?(bridge.last_error??'Connected · brief task updates go to PushWard.'):'Not connected · optional free-plan delivery.';
    const devicesKey=JSON.stringify(state.devices.map(device=>[device.id,device.name]));
    if(devicesKey!==bridgeDevicesKey){bridgeDevicesKey=devicesKey;byId('bridge-owner').replaceChildren(...state.devices.map(device=>{const option=document.createElement('option');option.value=device.id;option.textContent=device.name;return option;}));if(bridge.owner)byId('bridge-owner').value=bridge.owner;}
    const q=bridge.quota;byId('bridge-quota').textContent=q?`This month: ${q.activitiesUsed}/${q.activitiesLimit} Live Activity updates · ${q.notificationsUsed}/${q.notificationsLimit} alerts. `+(q.resetsAt?'Resets '+new Date(q.resetsAt).toLocaleString()+'.':''):'';
    for(const name of ['bridge-test','bridge-clear-test','bridge-refresh','bridge-disconnect'])byId(name).disabled=!bridge.enabled;
    if(state.error)byId('notice').textContent=state.error;
  }catch(error){notice(error);}
}
byId('connect').addEventListener('click',()=>api('/api/sign-in').then(refresh).catch(notice));
byId('check-models').addEventListener('click',async()=>{checkingModels=true;byId('check-models').disabled=true;byId('catalog-status').textContent='Checking model availability…';try{await api('/api/check-connection');}catch(error){notice(error);}finally{checkingModels=false;await refresh();}});
byId('pair').addEventListener('click',()=>api('/api/pairing',{base_url:byId('address').value}).then(result=>{byId('qr').src=result.qr;byId('pairing').hidden=false;notice(null);}).catch(notice));
const refreshTimer=setInterval(refresh,8000);refresh();
byId('quit').addEventListener('click',()=>api('/api/quit').then(()=>{clearInterval(refreshTimer);byId('notice').textContent='The companion is stopping. Work is saved; reopen the application to reconnect.';document.querySelectorAll('button,select').forEach(element=>{element.disabled=true;});}).catch(notice));

let taskView=null;
function element(tag,text,className){const node=document.createElement(tag);node.textContent=text;if(className)node.className=className;return node;}
async function openTask(job){taskView={id:job.id,cursor:0,nodes:new Map(),files:new Set(),busy:false};byId('task-title').textContent=job.title;byId('task-events').replaceChildren();byId('task-files').replaceChildren();byId('task-dialog').showModal();await refreshTask();}
async function refreshTask(){
  const view=taskView;if(!view||view.busy)return;view.busy=true;
  try{
    let value;const dirty=new Set();
    do{value=await api('/api/task',{job_id:view.id,after:view.cursor});if(taskView!==view)return;
      byId('task-state').textContent=labels[value.job.status]??value.job.status;
      for(const event of value.events){view.cursor=event.seq;const root=byId('task-events');
        const key=event.item_id??'round-'+(event.round??0);
        if(event.type==='text_delta'){let node=view.nodes.get(key);if(!node){node=element('div','','assistant-text');view.nodes.set(key,node);root.append(node);}node.sourceText=(node.sourceText??'')+(event.text??'');dirty.add(node);}
        if(event.type==='continuation')for(const item of event.output??[])if(item.type==='message'){
          const content=(item.content??[]).map(part=>part.text??part.refusal??'').join('');if(!content)continue;
          let node=view.nodes.get(item.id);if(!node){node=element('div','','assistant-text');view.nodes.set(item.id,node);root.append(node);}node.sourceText=content;dirty.add(node);
        }
        if(event.type==='pending_decisions')root.append(element('p',event.text+' '+(event.items??[]).map(item=>item.title).join(' · '),'task-step'));
        if(event.type==='activity')root.append(element('p',event.title,'task-step'));
        if(event.type==='phone_request'){
          const card=element('section','','review-card');view.nodes.set('review-'+event.call.id,card);
          const args=event.call.arguments??{};card.append(element('h3',args.title??args.question??'Your iPhone is needed'));
          card.append(element('p',args.detail??'Open this chat on your iPhone to continue.'));
          if(event.call.name==='review_computer_action')for(const approved of [true,false])card.append(action(approved?'Approve this action':'Cancel',async()=>{await api('/api/review',{job_id:view.id,operation_id:event.call.id,approved});card.querySelectorAll('button').forEach(button=>button.disabled=true);await refreshTask();}));root.append(card);
        }
        if(event.type==='pending_tool'||event.type==='executed_tool'){
          const prior=view.nodes.get('review-'+event.call.id);if(prior)prior.replaceChildren(element('p',event.result.output?.status==='approved'?'Action approved':'Review recorded'));
          const tool=event.call.name==='use_tool'?event.call.arguments?.name??event.call.name:event.call.name;
          const receiptKey='receipt-'+event.call.id;view.nodes.get(receiptKey)?.remove();const details=document.createElement('details');view.nodes.set(receiptKey,details);details.className='tool-receipt';details.append(element('summary',(event.type==='pending_tool'?'Pending · ':event.result.succeeded?'Completed · ':'Needs attention · ')+tool.replaceAll('_',' ')));
          const result=event.result.output??{};const text=result.output??result.stdout??result.text??result.error??result.verification??result.status??'Outcome saved';details.append(element('pre',String(text).slice(0,12000)));root.append(details);
        }
      }
      for(const node of dirty){node.innerHTML=DOMPurify.sanitize(marked.parse(node.sourceText??''),{USE_PROFILES:{html:true}});for(const link of node.querySelectorAll('a')){link.rel='noopener noreferrer';link.target='_blank';}}dirty.clear();
    }while(value.events.length&&view.cursor<value.job.cursor);
    for(const file of value.files??[])if(!view.files.has(file.id)&&['artifact','inspection'].includes(file.role)){
      view.files.add(file.id);byId('task-files').append(action('Download '+file.filename,async()=>{
        const value=await api('/api/file',{job_id:view.id,file_id:file.id}),bytes=Uint8Array.from(atob(value.data_base64),c=>c.charCodeAt(0));const url=URL.createObjectURL(new Blob([bytes]));const link=document.createElement('a');link.href=url;link.download=value.filename;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
      }));
    }
  }catch(error){notice(error);}finally{view.busy=false;}
}
byId('close-task').addEventListener('click',()=>{taskView=null;byId('task-dialog').close();});
byId('task-dialog').addEventListener('close',()=>{taskView=null;});
setInterval(refreshTask,2000);
byId('push-form').addEventListener('submit',async event=>{event.preventDefault();try{const file=byId('push-file').files[0];if(!file||file.size>8192)throw new Error('Choose the APNs .p8 key file.');await api('/api/push-configure',{team_id:byId('push-team').value.trim(),key_id:byId('push-key').value.trim(),topic:byId('push-topic').value.trim(),private_key:await file.text()});byId('push-file').value='';await refresh();}catch(error){notice(error);}});

byId('bridge-form').addEventListener('submit',async event=>{event.preventDefault();const button=event.currentTarget.querySelector('button');button.disabled=true;try{await api('/api/pushward-configure',{owner:byId('bridge-owner').value,key:byId('bridge-key').value.trim()});byId('bridge-key').value='';notice({message:'PushWard connected. Send a connection test, then check your iPhone.'});await refresh();}catch(error){notice(error);}finally{button.disabled=false;}});
byId('bridge-test').addEventListener('click',async()=>{byId('bridge-test').disabled=true;try{const result=await api('/api/pushward-test');notice({message:result.notice});}catch(error){notice(error);}finally{await refresh();}});
byId('bridge-clear-test').addEventListener('click',()=>api('/api/pushward-clear-test').then(()=>notice({message:'The connection-test activity was cleared.'})).catch(notice));
byId('bridge-refresh').addEventListener('click',()=>api('/api/pushward-refresh').then(refresh).catch(notice));
byId('bridge-disconnect').addEventListener('click',()=>api('/api/pushward-disconnect').then(refresh).catch(notice));
