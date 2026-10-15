import test from 'node:test';
import assert from 'node:assert/strict';
import { streamStructuredResponse } from '../vendor/siwc-local/dist/structured-responses.js';
const message={id:'answer',type:'message',role:'assistant',status:'completed',content:[{type:'output_text',text:'A synthetic completed answer.'}]};
const call={id:'tool',type:'function_call',status:'completed',call_id:'call1',name:'find_tools',arguments:'{"query":"documents"}'};
async function stream(events){
  const seen=[];
  const transport=async()=>new Response(events.map(e=>'data: '+JSON.stringify(e)+'\n\n').join('')+'data: [DONE]\n\n',{headers:{'content-type':'text/event-stream'}});
  const result=await streamStructuredResponse('synthetic-token',{body:{model:'synthetic',input:[]},onEvent:e=>seen.push(e.type)},new AbortController().signal,transport);
  return {result,seen};
}
test('real SDK SSE decoder retains item.done output when terminal output is empty',async()=>{
  const {result}=await stream([{type:'response.output_item.done',output_index:1,item:message},{type:'response.output_item.done',output_index:0,item:call},{type:'response.completed',response:{status:'completed',output:[]}}]);
  assert.deepEqual(result.output,[call,message]);
});
test('the terminal output is authoritative and never duplicates streamed output',async()=>{
  const {result}=await stream([{type:'response.output_item.done',output_index:0,item:message},{type:'response.completed',response:{status:'completed',output:[message]}}]);
  assert.deepEqual(result.output,[message]);
});
test('an ended stream or incomplete tool never authorizes a call',async()=>{
  await assert.rejects(stream([{type:'response.output_item.done',output_index:0,item:call}]),{code:'stream_interrupted'});
  await assert.rejects(stream([{type:'response.completed',response:{status:'completed',output:[{...call,status:'in_progress'}]}}]),{code:'response_incomplete'});
});

test('an output limit retains only public text and never authorizes incomplete tool calls',async()=>{
  await assert.rejects(stream([{type:'response.output_item.done',output_index:0,item:message},{type:'response.output_item.done',output_index:1,item:call},
    {type:'response.incomplete',response:{status:'incomplete',incomplete_details:{reason:'max_output_tokens'},output:[]}}]),error=>{
      assert.equal(error.code,'output_limit');assert.equal(error.partialOutput.length,1);assert.equal(error.partialOutput[0].type,'message');assert.equal(error.partialOutput[0].content[0].text,message.content[0].text);return true;
    });
});
