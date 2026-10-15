export async function jsonBody(request, maximum=8*1024*1024) {
  if (!String(request.headers['content-type']??'').toLowerCase().startsWith('application/json')) throw Object.assign(new Error('Use a JSON request.'),{status:415});
  const parts=[];let bytes=0;
  for await (const part of request) {bytes+=part.length;if(bytes>maximum)throw Object.assign(new Error('This request is too large.'),{status:413});parts.push(part);}
  try {return JSON.parse(Buffer.concat(parts).toString('utf8'));}catch{throw Object.assign(new Error('The request could not be read.'),{status:400});}
}
export function jsonReply(response,status,value) {
  response.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
  response.end(JSON.stringify(value));
}
export function validateJob(payload) {
  if (!payload || typeof payload!=='object' || typeof payload.request_key!=='string' || typeof payload.conversation_id!=='string' || typeof payload.turn_id!=='string') throw new Error('A task needs its conversation and request identifiers.');
  if (!payload.body || typeof payload.body.model!=='string' || !Array.isArray(payload.body.input)) throw new Error('A task needs a selected model and its input.');
  if (!Array.isArray(payload.catalog) || payload.catalog.length>150 || payload.catalog.some(t=>typeof t.name!=='string'||typeof t.description!=='string'||!t.parameters)) throw new Error('Invalid task tool catalog.');
  if(payload.start_when_ready!=null&&typeof payload.start_when_ready!=='boolean')throw new Error('Invalid task start policy.');
  if(payload.expected_file_ids!=null&&(!Array.isArray(payload.expected_file_ids)||payload.expected_file_ids.length>20||payload.expected_file_ids.some(id=>typeof id!=='string'||!/^[a-zA-Z0-9-]{1,80}$/.test(id))||new Set(payload.expected_file_ids).size!==payload.expected_file_ids.length))throw new Error('Invalid input manifest.');
  if(payload.server_context!=null&&(typeof payload.server_context!=='object'||Array.isArray(payload.server_context)||Buffer.byteLength(JSON.stringify(payload.server_context))>2*1024*1024))throw new Error('Invalid context snapshot.');
  const allowed=new Set(['model','input','instructions','tools','reasoning','include','parallel_tool_calls','text','store','stream']);
  if(Object.keys(payload.body).some(key=>!allowed.has(key)))throw new Error('The task contains unsupported model options.');
  if(payload.limits && (typeof payload.limits!=='object' || ['maximum_seconds','maximum_tool_calls','context_text_bytes','context_window_tokens'].some(key=>payload.limits[key]!=null&&(!Number.isSafeInteger(payload.limits[key])||payload.limits[key]<1))))throw new Error('Invalid task allowance.');
  return {...payload,body:{...payload.body,store:false,stream:true}};
}
