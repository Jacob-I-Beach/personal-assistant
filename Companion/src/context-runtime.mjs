const id=value=>String(value??'').toLowerCase();
const words=query=>String(query??'').toLowerCase().match(/[\p{L}\p{N}]+/gu)??[];
const matches=(text,query)=>!words(query).length||words(query).some(word=>text.toLowerCase().includes(word));
const characters=text=>Array.from(new Intl.Segmenter('en',{granularity:'grapheme'}).segment(text),item=>item.segment);
export const contextToolNames=new Set(['read_memory','search_history','read_history','update_plan','read_task']);
export function hasContext(call,job){
  const args=call.arguments??{},snapshot=job.payload.server_context;
  if(['update_plan','read_task'].includes(call.name))return !args.task_id||[id(job.id),id(job.payload.turn_id)].includes(id(args.task_id));
  if(!snapshot)return false;
  if(call.name==='read_memory'&&args.memory_id)return snapshot.memories?.some(note=>id(note.memory_id)===id(args.memory_id)&&(!args.offset||Number(args.offset)<characters(note.text).length));
  if(call.name==='read_history')return snapshot.history?.some(message=>id(message.message_id)===id(args.message_id)&&(!args.offset||Number(args.offset)<characters(message.text).length));
  return true;
}
export function contextResult(store,call,job){
  const args=call.arguments??{},snapshot=job.payload.server_context??{};let output;
  if(call.name==='search_history')output={matches:(snapshot.history??[]).filter(message=>matches(message.text,args.query)).slice(0,12).map(message=>({...message,text:undefined,excerpt:message.text.slice(0,500)})),coverage:snapshot.coverage};
  else if(call.name==='read_history'||call.name==='read_memory'){
    const memory=call.name==='read_memory',identifier=memory?args.memory_id:args.message_id,entries=memory?snapshot.memories:snapshot.history;
    if(memory&&!identifier)output=(entries??[]).filter(note=>matches(note.title+' '+note.text,args.query)).slice(0,4).map(note=>({...note,text:undefined,excerpt:note.text.slice(0,160)}));
    else{
      const item=(entries??[]).find(item=>id(memory?item.memory_id:item.message_id)===id(identifier)),offset=Number(args.offset)||0;
      if(!item||!Number.isSafeInteger(offset)||offset<0)throw new Error('That saved source or offset is unavailable.');
      const text=characters(item.text),end=Math.min(text.length,offset+(memory?1200:8000));
      output={...item,text:text.slice(offset,end).join(''),next_offset:end,snapshot_at:snapshot.captured_at,coverage:snapshot.coverage};
    }
  }else if(call.name==='update_plan'){
    const steps=typeof args.steps_json==='string'?JSON.parse(args.steps_json):args.steps_json;
    if(!Array.isArray(steps)||!steps.length||steps.length>8||steps.some(step=>typeof step.title!=='string'||!step.title||step.title.length>180||!['pending','in_progress','completed'].includes(step.status))||steps.filter(step=>step.status==='in_progress').length>1)throw new Error('Use 1–8 short steps with at most one in progress.');
    store.db.exec('CREATE TABLE IF NOT EXISTS task_plans(job_id TEXT PRIMARY KEY,data BLOB NOT NULL)');
    store.db.prepare('INSERT OR REPLACE INTO task_plans(job_id,data) VALUES(?,?)').run(job.id,store.vault.sealJSON(steps,'plan:'+job.id));output={steps};
  }else if(call.name==='read_task'){
    let plan=[];try{const row=store.db.prepare('SELECT data FROM task_plans WHERE job_id=?').get(job.id);if(row)plan=store.vault.openJSON(row.data,'plan:'+job.id);}catch{}
    const actions=store.db.prepare('SELECT id,status FROM operations WHERE job_id=? ORDER BY rowid DESC LIMIT 80').all(job.id).map(row=>({operation_id:row.id,status:row.status}));
    output={task_id:job.payload.turn_id,job_id:job.id,goal:job.payload.title,status:store.metadata(job.id,job.owner).status,plan,actions,files:store.files(job.id,job.owner),notice:'Read exact saved outcomes with read_task_output. Task state is owned by the computer.'};
  }else throw new Error('Unsupported context operation.');
  return {callID:call.id,name:call.name,succeeded:true,completedAt:new Date().toISOString(),output};
}
