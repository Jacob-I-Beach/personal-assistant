import {randomUUID} from 'node:crypto';

export class Scheduler {
  constructor(store,runner,{mayRun=()=>true,now=()=>Date.now()}={}){this.store=store;this.runner=runner;this.mayRun=mayRun;this.now=now;this.busy=false;}
  decode(row){return row?{id:row.id,owner:row.owner,enabled:!!row.enabled,...this.store.vault.openJSON(row.data,'schedule:'+row.id)}:null;}
  list(owner){return this.store.db.prepare('SELECT * FROM schedules WHERE owner=? ORDER BY rowid DESC LIMIT 100').all(owner).map(row=>this.decode(row));}
  save(schedule){const {id,owner,enabled,...data}=schedule;this.store.db.prepare('INSERT INTO schedules(id,owner,enabled,next_run,data) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET enabled=excluded.enabled,next_run=excluded.next_run,data=excluded.data').run(id,owner,enabled?1:0,data.runs.find(run=>run.status==='scheduled')?.at??null,this.store.vault.sealJSON(data,'schedule:'+id));}
  create(owner,body){
    if(typeof body.request_key!=='string'||body.request_key.length>200||!body.request_key)throw new Error('A schedule needs a stable request key.');
    const existing=this.list(owner).find(item=>item.request_key===body.request_key);
    if(existing){if(existing.prompt!==body.prompt||JSON.stringify(existing.runs.map(run=>run.at))!==JSON.stringify(body.run_at))throw Object.assign(new Error('This schedule request changed.'),{status:409});return existing;}
    if(typeof body.prompt!=='string'||!body.prompt.trim()||body.prompt.length>6000||typeof body.title!=='string'||body.title.length>120)throw new Error('Give the scheduled task a short title and request.');
    const times=body.run_at;
    if(!Array.isArray(times)||times.length<1||times.length>30||times.some((time,index)=>!Number.isSafeInteger(time)||time<this.now()-60000||time>this.now()+90*86400000||(index>0&&time-times[index-1]<15*60000)))throw new Error('Choose 1–30 future runs within 90 days, at least 15 minutes apart.');
    const source=this.store.get(body.source_job_id,owner);
    if(this.list(owner).filter(item=>item.enabled).length>=20)throw new Error('Pause or finish an existing schedule before adding another.');
    const selected=this.store.files(source.id,owner).filter(file=>file.role==='input');
    const inputFiles=selected.map(file=>({id:file.id,version:file.version,sha:file.sha}));
    const schedule={id:randomUUID(),owner,enabled:true,request_key:body.request_key,title:body.title,prompt:body.prompt,source_job_id:source.id,input_files:inputFiles,contains_health_data:source.payload.contains_health_data===true||selected.some(file=>file.contains_health_data===true),created_at:this.now(),runs:times.map(at=>({at,status:'scheduled',job_id:null}))};
    this.save(schedule);return schedule;
  }
  setEnabled(owner,id,enabled){const value=this.list(owner).find(item=>item.id===id);if(!value)throw new Error('Schedule not found.');value.enabled=enabled===true;this.save(value);return value;}
  stopOwner(owner){for(const value of this.list(owner)){value.enabled=false;this.save(value);}}
  async tick(){
    if(this.busy||this.stopped)return;this.busy=true;
    try{
      const schedules=this.store.db.prepare('SELECT * FROM schedules WHERE enabled=1').all().map(row=>this.decode(row));
      for(const schedule of schedules){
        const source=this.store.get(schedule.source_job_id,schedule.owner);
        if(!await this.mayRun(schedule.owner,source.payload.profile_id)||this.stopped)continue;
        for(const run of schedule.runs){
          if(run.job_id){run.status=this.store.get(run.job_id,schedule.owner).status;if(run.status==='interrupted'&&this.runner.active.size<4)this.runner.start(run.job_id,schedule.owner);continue;}
          if(run.status!=='scheduled'||run.at>this.now())continue;
          if(this.now()-run.at>6*3600000){run.status='missed';continue;}
          if(this.runner.active.size>=4)break;
          const turn=randomUUID(),conversation=randomUUID();
          const body=structuredClone(source.payload.body);
          body.input=[{role:'user',content:[{type:'input_text',text:schedule.prompt}]}];
          body.tools=(body.tools??[]).filter(tool=>tool.type==='web_search');
          body.instructions='You are Personal Assistant running a user-approved scheduled task on their computer. Complete the stated research, analysis or draft using the provided computer tools. This unattended run may research public information and create files only. It cannot send messages, change calendars, access new phone data or create another schedule. Source files are the snapshots explicitly attached to the original task, not automatically refreshed. Report the result and evidence concisely. Current time: '+new Date(this.now()).toISOString();
          const key='schedule:'+schedule.id+':'+run.at;
          const existing=this.store.find(schedule.owner,key);
          const job=existing??this.store.create(schedule.owner,key,{request_key:key,conversation_id:conversation,turn_id:turn,profile_id:source.payload.profile_id,title:schedule.title,display_prompt:schedule.prompt,schedule_id:schedule.id,presentation:source.payload.presentation,contains_health_data:schedule.contains_health_data===true||source.payload.contains_health_data===true,body,catalog:[],limits:{maximum_seconds:600,maximum_tool_calls:12}}).job;
          for(const file of (schedule.input_files??[]).filter(file=>!this.store.files(job.id,schedule.owner).some(saved=>saved.id===file.id))){
            const original=this.store.file(source.id,schedule.owner,file.id,file.version);
            if(original.metadata.sha!==file.sha)throw new Error('A scheduled source snapshot no longer matches its recorded version.');
            this.store.saveFile(job.id,{...original.metadata,version:undefined,sha:undefined},original.data);
          }
          run.job_id=job.id;run.status=job.status;this.save(schedule);
          if(['queued','interrupted'].includes(job.status))this.runner.start(job.id,schedule.owner);
        }
        if(schedule.runs.every(run=>!['scheduled','queued','running','waiting_for_phone','waiting_for_input','interrupted'].includes(run.status)))schedule.enabled=false;
        this.save(schedule);
      }
    }finally{this.busy=false;}
  }
}
