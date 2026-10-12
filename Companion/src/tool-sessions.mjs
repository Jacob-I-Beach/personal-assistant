import {normalizeArguments} from './tool-arguments.mjs';

/** Isolated computer tools are callable without routing model inference here. */
export class ToolSessions {
  constructor(store,runtime){this.store=store;this.runtime=runtime;this.active=new Map();}
  create(owner,body){
    if(typeof body.request_key!=='string'||body.request_key.length>200||typeof body.conversation_id!=='string')throw new Error('A saved chat and turn are required.');
    return this.store.create(owner,'tools:'+body.request_key,{execution_only:true,conversation_id:body.conversation_id,turn_id:body.request_key,title:'Computer tools',contains_health_data:body.contains_health_data===true}).job;
  }
  start(id,owner,call){
    const job=this.store.get(id,owner),definition=this.runtime.definitions.find(tool=>tool.name===call.name);
    if(!job.payload.execution_only||!definition||!/^[a-zA-Z0-9_-]{1,200}$/.test(call.id??''))throw new Error('This computer action is unavailable.');
    if(job.status==='cancelled')throw new Error('This work was stopped.');
    call={...call,arguments:normalizeArguments(call.arguments,definition.parameters)};
    const prior=this.store.beginOperation(id,call.id,call,'computer'),key=id+':'+call.id;
    if(prior.result)return {status:'completed',result:prior.result};
    if(prior.status!=='new')return {status:this.active.has(key)?'running':'outcome_unknown'};
    const abort=new AbortController();
    const promise=this.runtime.execute(call,job,abort.signal).catch(error=>({callID:call.id,name:call.name,succeeded:false,output:{status:'failed',error:error.publicMessage??'The computer tool could not finish. Its recorded results are kept.'}}))
      .then(result=>this.store.finishOperation(id,call.id,result)).finally(()=>this.active.delete(key));
    this.active.set(key,{abort,promise});
    return {status:'running'};
  }
  async close(){for(const item of this.active.values())item.abort.abort(new Error('Computer stopped'));await Promise.all([...this.active.values()].map(item=>item.promise));}
  cancel(id,owner){
    const job=this.store.get(id,owner);if(!job.payload.execution_only)throw new Error('This is not a tool workspace.');
    for(const [key,item] of this.active)if(key.startsWith(id+':'))item.abort.abort(new Error('Stopped by the user'));
    if(job.status!=='cancelled')this.store.status(id,'cancelled','Stopped by the user. Saved results are kept.');
    return this.store.metadata(id,owner);
  }
  async prepareHandoff(job){
    const input=structuredClone(job.payload.body.input),sourceID=job.payload.source_tool_session_id;
    if(!sourceID)return {input,receipts:[]};
    const source=this.store.get(sourceID,job.owner);
    if(!source.payload.execution_only||source.payload.turn_id!==job.payload.turn_id||source.payload.conversation_id!==job.payload.conversation_id)throw new Error('Invalid tool workspace handoff.');
    await Promise.all([...this.active.entries()].filter(([key])=>key.startsWith(sourceID+':')).map(([,item])=>item.promise));
    const copied=new Set(this.store.files(job.id,job.owner).map(file=>file.id));
    for(const metadata of this.store.files(sourceID,job.owner))if(!copied.has(metadata.id))this.store.saveFile(job.id,{...metadata},this.store.file(sourceID,job.owner,metadata.id).data);
    const receipts=[];
    for(const item of input.filter(item=>item.type==='function_call')){
      let operation;try{operation=this.store.operation(sourceID,item.call_id);}catch{continue;}
      const result=operation.result??{callID:item.call_id,name:operation.request.name,succeeded:false,output:{status:'outcome_unknown',error:'The previous computer tool has no final receipt. Inspect its saved outputs before repeating it.'}};
      const value={type:'function_call_output',call_id:item.call_id,output:JSON.stringify({...result.output,tool_succeeded:result.succeeded,operation_id:item.call_id})};
      const index=input.findIndex(candidate=>candidate.type==='function_call_output'&&candidate.call_id===item.call_id);
      let old;try{old=index>=0?JSON.parse(input[index].output):null;}catch{}
      if(index>=0)input[index]=value;else input.push(value);
      if(index<0||old?.status==='outcome_unknown'||old?.tool_succeeded!==result.succeeded)receipts.push({call:{id:item.call_id,name:item.name.replace(/^assistant\./,''),arguments:JSON.parse(item.arguments)},result});
    }
    return {input,receipts};
  }
}
