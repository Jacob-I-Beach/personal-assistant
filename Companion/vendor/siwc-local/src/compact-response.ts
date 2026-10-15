import OpenAI from 'openai';
import {apiError,ChatGPTError,isObject} from './errors.js';
import type {StructuredResponseOptions} from './types.js';

/** Optional same-account capability. Unsupported OAuth routes fall back in the
 * coordinator; no Platform key, tenant, credential copy or billing setup. */
export async function compactResponse(accessToken:string,options:StructuredResponseOptions,signal:AbortSignal,transport:typeof fetch=fetch):Promise<Record<string,unknown>> {
  const allowed=new Set(['model','input','instructions']);
  if(Object.keys(options.body).some(key=>!allowed.has(key))||typeof options.body.model!=='string'||!Array.isArray(options.body.input))throw new ChatGPTError('invalid_request','Invalid compaction request.');
  const client=new OpenAI({apiKey:accessToken,baseURL:'https://api.openai.com/v1',organization:null,project:null,logLevel:'warn',maxRetries:0,
    fetch:transport,fetchOptions:{redirect:'error'},defaultHeaders:{authorization:`Bearer ${accessToken}`,'openai-organization':null,'openai-project':null}});
  try{
    const result=await client.responses.compact(options.body as unknown as OpenAI.Responses.ResponseCompactParams,{signal:AbortSignal.any([signal,AbortSignal.timeout(180000)])});
    if(!isObject(result)||!Array.isArray(result.output)||!result.output.length||!result.output.some(item=>isObject(item)&&item.type==='compaction'&&typeof item.encrypted_content==='string'))throw new ChatGPTError('invalid_compaction','The connection did not return replayable compacted state.');
    if(Buffer.byteLength(JSON.stringify(result))>16*1024*1024)throw new ChatGPTError('invalid_compaction','The compacted result exceeded its size allowance.');
    return result as unknown as Record<string,unknown>;
  }catch(error){
    if(signal.aborted)throw new ChatGPTError('cancelled','Compaction was stopped.');
    if(error instanceof ChatGPTError)throw error;
    if(error instanceof OpenAI.APIError&&!(error instanceof OpenAI.APIConnectionError))throw apiError(error.error,error.status,error.requestID??undefined);
    throw new ChatGPTError('compaction_unavailable','Native compaction could not finish. Exact source context is retained.',true);
  }
}
