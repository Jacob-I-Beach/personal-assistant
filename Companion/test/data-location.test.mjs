import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,readFile,writeFile,cp,stat,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {computerDataRoot,resolveComputerDataRoot} from '../src/data-location.mjs';

async function fixture(){
  const folder=await mkdtemp(join(tmpdir(),'assistant-location-'));
  return {folder,profile:join(folder,'profile'),localAppData:join(folder,'app-data'),close:()=>rm(folder,{recursive:true,force:true})};
}
async function legacy(root,{jobs=0,devices=0,key='synthetic key'}={}){
  await mkdir(join(root,'tls'),{recursive:true});await mkdir(join(root,'chatgpt'));
  await writeFile(join(root,'work-key.protected'),key);
  await writeFile(join(root,'tls','certificate.pem'),'synthetic certificate');
  await writeFile(join(root,'chatgpt','opaque-account'),'synthetic encrypted account fixture');
  const db=new DatabaseSync(join(root,'work.db'));
  db.exec('PRAGMA journal_mode=WAL; CREATE TABLE devices(id INTEGER PRIMARY KEY,revoked INTEGER); CREATE TABLE jobs(id INTEGER PRIMARY KEY);');
  for(let i=0;i<devices;i++)db.prepare('INSERT INTO devices VALUES (?,0)').run(i);
  for(let i=0;i<jobs;i++)db.prepare('INSERT INTO jobs VALUES (?)').run(i);
  return db;
}
const cache=f=>join(f.localAppData,'Packages','OpenAI.Codex_fixture','LocalCache','Local','PersonalAssistantCompanion');

test('migration selects the populated MSIX store over an empty normal-launch store, preserving committed WAL work and opaque account files',async()=>{
  const f=await fixture();let source;
  try{
    (await legacy(join(f.localAppData,'PersonalAssistantCompanion'))).close();
    source=await legacy(cache(f),{jobs:3,devices:2});
    const root=await resolveComputerDataRoot(f);
    assert.equal(root,computerDataRoot(f.profile));
    const db=new DatabaseSync(join(root,'work.db'),{readOnly:true});
    try{assert.equal(db.prepare('SELECT COUNT(*) AS n FROM jobs').get().n,3);assert.equal(db.prepare('SELECT COUNT(*) AS n FROM devices').get().n,2);}finally{db.close();}
    assert.equal(await readFile(join(root,'tls','certificate.pem'),'utf8'),'synthetic certificate');
    assert.equal(await readFile(join(root,'chatgpt','opaque-account'),'utf8'),'synthetic encrypted account fixture');
    assert.equal(source.prepare('SELECT COUNT(*) AS n FROM jobs').get().n,3);
    assert.equal(JSON.parse(await readFile(join(root,'migration.json'),'utf8')).original_preserved,true);
    assert.equal(await resolveComputerDataRoot(f),root);
  }finally{source?.close();await f.close();}
});
test('equivalent legacy paths do not create an ambiguous migration',async()=>{
  const f=await fixture();try{
    const ordinary=join(f.localAppData,'PersonalAssistantCompanion');(await legacy(ordinary,{jobs:1})).close();
    await cp(ordinary,cache(f),{recursive:true});
    assert.equal(await resolveComputerDataRoot(f),computerDataRoot(f.profile));
  }finally{await f.close();}
});
test('competing populated stores are preserved and require a deliberate choice',async()=>{
  const f=await fixture();try{
    (await legacy(join(f.localAppData,'PersonalAssistantCompanion'),{jobs:1,key:'first fixture'})).close();
    (await legacy(cache(f),{devices:1,key:'second fixture'})).close();
    await assert.rejects(resolveComputerDataRoot(f),/More than one existing/);
    await assert.rejects(stat(computerDataRoot(f.profile)),{code:'ENOENT'});
  }finally{await f.close();}
});
test('a fresh installation uses the same explicit location without a legacy store',async()=>{
  const f=await fixture();try{
    assert.equal(await resolveComputerDataRoot(f),computerDataRoot(f.profile));
    assert.ok((await stat(computerDataRoot(f.profile))).isDirectory());
  }finally{await f.close();}
});
