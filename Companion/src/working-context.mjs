function weight(value){
  if(typeof value==='string')return value.startsWith('data:image/')?16000:value.length;
  if(Array.isArray(value))return value.reduce((sum,item)=>sum+weight(item),0);
  if(value&&typeof value==='object')return Object.entries(value).reduce((sum,[key,item])=>sum+key.length+weight(item),0);
  return 8;
}
function receiptExcerpt(text,callId,maximum){
  if(typeof text!=='string'||text.length<=maximum)return text;
  let original;try{original=JSON.parse(text);}catch{}
  const kept={};
  for(const key of ['status','tool_succeeded','operation_id','completed_at','execution_location','files','state_file','question','answer'])if(original?.[key]!=null)kept[key]=original[key];
  return JSON.stringify({...kept,working_excerpt:text.slice(0,maximum),full_result_operation_id:callId,notice:'This is an excerpt for working context. The complete saved receipt can be read with read_task_output; use computer file handles for datasets. Do not repeat a completed action.'});
}
export function compactWorkingContext(input,{budget=750000,protectedStart=0}={}){
  const ceiling=Math.max(16000,Math.min(4000000,budget));
  if(weight(input)<=ceiling)return {input,compacted:false};
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
  return {input:result,compacted:true,protectedStart:input.slice(0,recent).filter(item=>item.type!=='reasoning').length};
}
