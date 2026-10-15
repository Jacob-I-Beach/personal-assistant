import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {normalizeArguments} from '../src/tool-arguments.mjs';
const fixtures=JSON.parse(readFileSync(new URL('../../Sources/AssistantCore/Resources/ProtocolParity.json',import.meta.url),'utf8'));
test('Swift and computer consume the same argument behavior fixtures',()=>{
  for(const item of fixtures.normalization){
    if(item.error)assert.throws(()=>normalizeArguments(item.input,item.schema),item.name);
    else assert.deepEqual(JSON.parse(JSON.stringify(normalizeArguments(item.input,item.schema))),item.expected,item.name);
  }
});
