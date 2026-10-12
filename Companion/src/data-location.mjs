import {cp,mkdir,readFile,readdir,rename,stat,writeFile} from 'node:fs/promises';
import {basename,dirname,join,resolve} from 'node:path';
import {homedir} from 'node:os';
import {createHash,randomUUID} from 'node:crypto';
import {backup,DatabaseSync} from 'node:sqlite';

export function computerDataRoot(profile=process.env.USERPROFILE??homedir()) {
  // LocalAppData is virtualized for processes launched from MSIX apps. A
  // user-profile folder has the same identity for the launcher and its tools.
  return resolve(profile,'.personal-assistant','computer');
}
async function exists(path){try{await stat(path);return true;}catch(error){if(error.code==='ENOENT')return false;throw error;}}
async function storeInfo(root){
  const database=join(root,'work.db'),key=join(root,'work-key.protected');
  if(!await exists(database)||!await exists(key))return null;
  const db=new DatabaseSync(database,{readOnly:true});
  let devices,jobs;
  try{
    devices=db.prepare('SELECT COUNT(*) AS n FROM devices WHERE revoked=0').get().n;
    jobs=db.prepare('SELECT COUNT(*) AS n FROM jobs').get().n;
  }finally{db.close();}
  // Deduplicate the same legacy store seen through a virtualized and physical
  // path. These digests stay in memory; no keys or conversation data are logged.
  const digest=createHash('sha256');
  for(const path of [key,database,database+'-wal'])if(await exists(path))digest.update(await readFile(path));
  return {root,devices,jobs,identity:digest.digest('hex')};
}

export async function resolveComputerDataRoot({profile=process.env.USERPROFILE??homedir(),localAppData=process.env.LOCALAPPDATA}={}) {
  const root=computerDataRoot(profile);
  if(await exists(join(root,'work-key.protected')))return root;
  const candidates=[];
  if(localAppData){
    candidates.push(join(localAppData,'PersonalAssistantCompanion'));
    const packages=join(localAppData,'Packages');
    let names=[];try{names=await readdir(packages);}catch(error){if(error.code!=='ENOENT')throw error;}
    for(const name of names.filter(name=>/^OpenAI\.Codex_/i.test(name)))candidates.push(join(packages,name,'LocalCache','Local','PersonalAssistantCompanion'));
  }
  const unique=new Map();
  for(const candidate of candidates){const info=await storeInfo(candidate);if(info)unique.set(info.identity,info);}
  const stores=[...unique.values()],populated=stores.filter(store=>store.devices>0||store.jobs>0);
  if(populated.length>1)throw new Error('More than one existing companion data store contains work. Keep both stores; choose the original data location before migrating.');
  const previous=populated[0]??stores[0];
  if(!previous){await mkdir(root,{recursive:true});return root;}
  if(await exists(root))throw new Error('The new companion data location already contains an incomplete store. Its files were preserved; finish recovery before migrating.');
  await mkdir(dirname(root),{recursive:true});
  const staging=join(dirname(root),'migration-'+randomUUID());
  await mkdir(staging);
  // Keep the entire original store. SQLite backup includes committed WAL
  // transactions without copying a torn database or deleting its old journal.
  await cp(previous.root,staging,{recursive:true,filter:path=>!(dirname(path)===previous.root&&/^work\.db(?:-wal|-shm)?$/.test(basename(path)))});
  const source=new DatabaseSync(join(previous.root,'work.db'),{readOnly:true});
  try{await backup(source,join(staging,'work.db'));}finally{source.close();}
  const copied=await storeInfo(staging);
  if(!copied||copied.devices!==previous.devices||copied.jobs!==previous.jobs)throw new Error('The saved work changed during migration. The original and staged files were preserved; stop the previous service before retrying.');
  await writeFile(join(staging,'migration.json'),JSON.stringify({from:previous.root,migrated_at:new Date().toISOString(),devices:copied.devices,jobs:copied.jobs,original_preserved:true},null,2));
  await rename(staging,root);
  return root;
}
