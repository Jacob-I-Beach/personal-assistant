import test from 'node:test';
import assert from 'node:assert/strict';
import {compactWorkingContext,contextWeight} from '../src/working-context.mjs';

test('the whole request budget includes instructions, tools and multibyte input',()=>{
  const input=[{role:'user',content:'漢'.repeat(2000)}],original=structuredClone(input);
  assert.equal(contextWeight('漢'),3);
  assert.throws(()=>compactWorkingContext(input,{budget:8000,instructions:'x'.repeat(2000),tools:[{description:'x'.repeat(1000)}]}),error=>error.code==='context_limit');
  assert.deepEqual(input,original,'never truncate the actual user request to make it fit');
  assert.equal(compactWorkingContext(input,{budget:10000,instructions:'short',tools:[]}).compacted,false);
});

test('unreducible saved context fails before an oversized provider request',()=>{
  assert.throws(()=>compactWorkingContext([{role:'user',content:'x'.repeat(40000)}],{budget:16000}),error=>error.code==='context_limit');
});

test('large saved tool results compact without losing receipt identity or changing the original request',()=>{
  const input=[{role:'user',content:[{type:'input_text',text:'Keep working on the original request.'}]},
    {type:'reasoning',encrypted_content:'opaque-previous-context'},
    {type:'function_call',call_id:'effect',name:'reviewed_action',arguments:'{}'},
    {type:'function_call_output',call_id:'effect',output:JSON.stringify({status:'sent',tool_succeeded:true,operation_id:'effect',result:'x'.repeat(120000)})},
    {type:'message',role:'assistant',content:[{type:'output_text',text:'I will use the saved result.'}]}];
  const compact=compactWorkingContext(input,{budget:20000,protectedStart:4});
  assert.equal(compact.compacted,true);assert.deepEqual(compact.input[0],input[0]);
  assert.equal(compact.input.some(item=>item.type==='reasoning'),false);
  const saved=compact.input.find(item=>item.type==='function_call_output'),receipt=JSON.parse(saved.output);
  assert.equal(saved.call_id,'effect');assert.equal(receipt.status,'sent');assert.equal(receipt.tool_succeeded,true);assert.equal(receipt.full_result_operation_id,'effect');
  assert.ok(saved.output.length<5000);assert.ok(input[3].output.length>120000);
});
