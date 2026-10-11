const byId=id=>document.getElementById(id),csrf=document.querySelector('meta[name="csrf-token"]').content;
async function api(path,body={}){const response=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json','X-Assistant-CSRF':csrf},body:JSON.stringify(body)});const value=await response.json();if(!response.ok)throw new Error(value.error??'The request could not finish.');return value;}
function notice(error){byId('notice').textContent=error?.message??'';}
const labels={queued:'Waiting to start',running:'Working',waiting_for_phone:'Needs your iPhone',waiting_for_input:'Needs your answer',completed:'Ready',failed:'Needs attention',cancelled:'Stopped',interrupted:'Ready to continue'};
function action(text,handler){const button=document.createElement('button');button.textContent=text;button.addEventListener('click',()=>handler().catch(notice));return button;}
let addressesKey='';
async function refresh(){
  try{const state=await api('/api/status');const session=state.session;
    byId('account').textContent=session.status==='connected'?(session.sharing?'Connected · '+(session.identity?.name??session.profileLabel??'ChatGPT plan'):'Connected; plan sharing needs authorization'):'Connect the ChatGPT account you want this computer to use.';
    byId('connect').textContent=session.status==='connecting'?'Waiting for browser authorization…':session.status==='connected'?'Reconnect ChatGPT':'Continue with ChatGPT';byId('connect').disabled=session.status==='connecting';
    byId('compute').textContent=state.computation_ready?'Ready for Python, spreadsheets, documents and page inspection.':'The computation service is not ready yet. Start Docker Desktop and finish the companion setup.';
    const key=JSON.stringify(state.addresses);if(key!==addressesKey){addressesKey=key;byId('address').replaceChildren(...state.addresses.map(item=>{const option=document.createElement('option');option.value=item.url;option.textContent=item.label+' · '+new URL(item.url).hostname;return option;}));}byId('pair').disabled=!state.addresses.length;
    byId('count').textContent=state.jobs.length?state.jobs.length+' task'+(state.jobs.length===1?'':'s'):'';byId('jobs').replaceChildren();
    if(!state.jobs.length){const empty=document.createElement('p');empty.className='empty';empty.textContent='Tasks from your iPhone will appear here.';byId('jobs').append(empty);}
    for(const job of state.jobs){const row=document.createElement('div');row.className='job';const content=document.createElement('div'),title=document.createElement('h3'),detail=document.createElement('p');title.textContent=job.title;detail.textContent=(labels[job.status]??job.status)+' · '+job.model;content.append(title,detail);row.append(content);if(!['completed','cancelled','failed','interrupted'].includes(job.status))row.append(action('Stop',()=>api('/api/cancel',{job_id:job.id}).then(refresh)));byId('jobs').append(row);}
    byId('devices').replaceChildren(...state.devices.map(device=>{const row=document.createElement('div');row.className='device';const label=document.createElement('span');label.textContent=device.name;row.append(label,action('Disconnect',()=>api('/api/revoke',{device_id:device.id}).then(refresh)));return row;}));
    if(state.error)byId('notice').textContent=state.error;
  }catch(error){notice(error);}
}
byId('connect').addEventListener('click',()=>api('/api/sign-in').then(refresh).catch(notice));
byId('pair').addEventListener('click',()=>api('/api/pairing',{base_url:byId('address').value}).then(result=>{byId('qr').src=result.qr;byId('pairing').hidden=false;notice(null);}).catch(notice));
refresh();setInterval(refresh,8000);
