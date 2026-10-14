import {open,readFile,lstat,rename,link,unlink,chmod} from 'node:fs/promises';
import {dirname,join,basename,resolve} from 'node:path';
import {createHash,randomUUID} from 'node:crypto';

const locks=new Map(),hash=bytes=>createHash('sha256').update(bytes).digest('hex');
async function cancelledWait(promise,signal){
  signal.throwIfAborted();
  await new Promise((resolveWait,reject)=>{
    const abort=()=>reject(signal.reason??new Error('Stopped'));
    signal.addEventListener('abort',abort,{once:true});
    promise.then(resolveWait,reject).finally(()=>signal.removeEventListener('abort',abort));
    if(signal.aborted)abort();
  });
}
async function snapshot(path){
  try{
    const info=await lstat(path,{bigint:true});
    if(!info.isFile()||info.isSymbolicLink())throw new Error('The target must be a regular file.');
    const data=await readFile(path),after=await lstat(path,{bigint:true});
    if(info.ino!==after.ino||info.dev!==after.dev||info.mtimeNs!==after.mtimeNs||info.size!==after.size)throw new Error('The file changed while it was being read.');
    return {info,data,sha:hash(data)};
  }catch(error){if(error.code==='ENOENT')return null;throw error;}
}

/** Atomic replacement and serialization among assistant tasks. The filesystem
 * has no hash-conditional rename: unrelated programs that rename this target at
 * the last instant cannot be given a stronger compare-and-swap guarantee. */
export async function replaceTextFile({path,data,expectedHash,signal,revalidate=async()=>path,savePrevious=()=>{},beforeCommit=async()=>{}}){
  const key=process.platform==='win32'?resolve(path).toLowerCase():resolve(path),previous=locks.get(key)??Promise.resolve();
  let unlock;const lease=new Promise(r=>{unlock=r;}),tail=previous.then(()=>lease);locks.set(key,tail);
  tail.then(()=>{if(locks.get(key)===tail)locks.delete(key);});
  let temporary;
  try{
    await cancelledWait(previous,signal);signal.throwIfAborted();
    const original=await snapshot(path);
    if(original?original.sha!==expectedHash:!!expectedHash)throw new Error('This file changed. Read its current version before replacing it.');
    temporary=join(dirname(path),'.'+basename(path)+'.assistant-'+randomUUID()+'.tmp');
    const file=await open(temporary,'wx',0o600);
    try{await file.writeFile(data);await file.sync();}finally{await file.close();}
    if(original)await chmod(temporary,Number(original.info.mode&0o777n));
    if(original)await savePrevious(original.data);
    await beforeCommit();signal.throwIfAborted();
    const checked=resolve(await revalidate());
    if((process.platform==='win32'?checked.toLowerCase():checked)!==key)throw new Error('The target folder or file identity changed.');
    const current=await snapshot(path);
    if(original?(!current||current.sha!==original.sha||current.info.ino!==original.info.ino||current.info.dev!==original.info.dev):!!current)throw new Error('Another edit changed this file before saving. Read it again.');
    signal.throwIfAborted();
    if(current)await rename(temporary,path);
    else{await link(temporary,path);await unlink(temporary);}
    temporary=null;
    const saved=await readFile(path),sha=hash(data);
    if(hash(saved)!==sha)throw Object.assign(new Error('The saved file changed during final verification. Inspect its current contents before trying another edit.'),{code:'outcome_unknown'});
    return {sha256:sha,bytes:data.length,verification:'Atomic replacement; version and file identity checked immediately before commit. Assistant writes are serialized. An unrelated program can still race a final filesystem rename.'};
  }finally{
    if(temporary)await unlink(temporary).catch(()=>{});
    unlock();
  }
}
