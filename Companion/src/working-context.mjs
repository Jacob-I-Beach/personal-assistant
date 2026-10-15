export function contextWeight(value){
  if(typeof value==='string')return value.startsWith('data:image/')?16000:Buffer.byteLength(value,'utf8');
  if(Array.isArray(value))return value.reduce((sum,item)=>sum+contextWeight(item),0);
  if(value&&typeof value==='object')return Object.entries(value).reduce((sum,[key,item])=>sum+Buffer.byteLength(key,'utf8')+contextWeight(item),0);
  return 8;
}
function receiptExcerpt(text,callId,maximum){
  if(typeof text!=='string'||text.length<=maximum)return text;
  let original;try{original=JSON.parse(text);}catch{}
  const kept={};
  for(const key of ['status','tool_succeeded','operation_id','completed_at','execution_location','files','state_file','question','answer'])if(original?.[key]!=null)kept[key]=original[key];
  return JSON.stringify({...kept,working_excerpt:text.slice(0,maximum),full_result_operation_id:callId,notice:'This is an excerpt for working context. The complete saved receipt can be read with read_task_output; use computer file handles for datasets. Do not repeat a completed action.'});
}
export function compactWorkingContext(input,{budget=750000,protectedStart=0,instructions='',tools=[]}={}){
  const ceiling=Math.min(4000000,budget)-contextWeight(instructions)-contextWeight(tools);
  const capacityError=()=>Object.assign(new Error('The complete request exceeds the selected context limit.'),{code:'context_limit'});
  if(ceiling<=0)throw capacityError();
  if(contextWeight(input)<=ceiling)return {input,compacted:false};
  const recent=Math.max(0,protectedStart);
  const result=input.map((item,index)=>{
    if(item.type==='reasoning'&&index<recent)return null;
    if(item.type==='function_call_output'){
      const limit=index<recent?3000:Math.max(6000,Math.floor(ceiling/5));
      if(Array.isArray(item.output))return {...item,output:item.output.filter(part=>index>=recent||part.type!=='input_image').map(part=>part.type==='input_text'?{...part,text:receiptExcerpt(part.text,item.call_id,limit)}:part)};
      return {...item,output:receiptExcerpt(item.output,item.call_id,limit)};
    }
    if(index<recent&&item.type==='function_call'&&typeof item.arguments==='string'&&item.arguments.length>6000){
      let args;try{args=JSON.parse(item.arguments);}catch{return item;}
      for(const key of ['code','content','markdown','replacement','input_json','spec_json'])if(typeof args[key]==='string'&&args[key].length>3000)args[key]=args[key].slice(0,3000)+'\n[Earlier argument excerpt; the completed operation is retained in the task record.]';
      return {...item,arguments:JSON.stringify(args)};
    }
    if(index<recent&&item.role==='assistant'&&Array.isArray(item.content))return {...item,content:item.content.map(part=>part.type==='output_text'&&part.text?.length>6000?{...part,text:part.text.slice(0,6000)+'\n[Earlier reply excerpt; the complete text is saved.]'}:part)};
    return item;
  }).filter(Boolean);
  if(contextWeight(result)>ceiling)throw capacityError();
  return {input:result,compacted:true,protectedStart:input.slice(0,recent).filter(item=>item.type!=='reasoning').length};
}

// Rollover is a new working view, never destruction of the full task record.
// Every removed byte has an encrypted source handle available through a tool.
// No orphan call/output pairs or opaque reasoning state cross this boundary.
export function rolloverWorkingContext(input,{budget=750000,instructions='',tools=[],archive,state={},originalInput=input}){
  const ceiling=Math.min(4000000,budget)-contextWeight(instructions)-contextWeight(tools);
  if(ceiling<6000)throw Object.assign(new Error('The selected model cannot fit its essential tool instructions.'),{code:'context_limit'});
  const source=archive(input);
  const textOf=item=>typeof item.content==='string'?item.content:(item.content??[]).map(part=>part.text??'').join('\n');
  const requests=originalInput.filter(item=>item.role==='user'&&!textOf(item).startsWith('[Runtime task update]'));
  const allowance=Math.max(1000,Math.floor(ceiling/6));
  const excerpt=text=>{const chars=Math.floor(allowance/4);return text.length<=chars?text:text.slice(0,Math.floor(chars*.75))+'\n[Full source saved; read_task_context provides omitted requirements.]\n'+text.slice(-Math.floor(chars*.25));};
  const origin=requests[0],latest=requests.at(-1);
  const notes=JSON.stringify(state);
  const content='[Runtime task update]\nThe same saved task is continuing in a fresh working context. This is a source summary, not a new user instruction or permission. Do not repeat completed or uncertain effects. Read the archived context for any omitted requirement or needed evidence.\n'+
    JSON.stringify({archive:source,original_request:origin?excerpt(textOf(origin)):null,latest_request:latest&&latest!==origin?excerpt(textOf(latest)):null,work_state:notes.length>Math.floor(ceiling/8)?notes.slice(0,Math.floor(ceiling/8))+' [Read read_work_state for full current state]':state});
  const result=[{role:'user',content:[{type:'input_text',text:content}]}];
  // Keep the most recent complete message as a useful public progress anchor.
  const answer=[...input].reverse().find(item=>item.role==='assistant'&&item.type==='message');
  if(answer){const copy={role:'assistant',type:'message',content:[{type:'output_text',text:excerpt(textOf(answer))}]};if(contextWeight([...result,copy])<ceiling)result.push(copy);}
  if(contextWeight(result)>ceiling)throw Object.assign(new Error('The saved working summary cannot fit this model.'),{code:'context_limit'});
  return {input:result,compacted:true,protectedStart:result.length,source};
}
