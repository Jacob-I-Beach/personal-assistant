import { spawn } from 'node:child_process';
import { X509Certificate, randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile, unlink, access, rename } from 'node:fs/promises';
import { join } from 'node:path';
import { credentialEncryption } from './vault.mjs';

export async function certificate(root) {
  const folder = join(root,'tls'), publicPath=join(folder,'certificate.pem'), privatePath=join(folder,'private-key.protected');
  await mkdir(folder,{recursive:true});
  let cert, key;
  try { cert=await readFile(publicPath); key=await credentialEncryption.decrypt(await readFile(privatePath)); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    const existing=await Promise.all([publicPath,privatePath].map(path=>access(path).then(()=>true,()=>false)));
    if(existing.some(Boolean))throw new Error('The saved computer certificate is incomplete. Keep its files and repair the connection before pairing again.');
    const temporary=join(folder,'pending-'+randomUUID()+'.key');
    const pendingCertificate=temporary+'.pem';
    try {
      await new Promise((resolve,reject)=>{
        const child=spawn('C:\\Program Files\\Git\\usr\\bin\\openssl.exe',['req','-x509','-newkey','rsa:3072','-sha256','-days','1825','-nodes','-keyout',temporary,'-out',pendingCertificate,'-subj','/CN=Personal Assistant Computer','-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'],{windowsHide:true,stdio:'ignore',shell:false});
        const timer=setTimeout(()=>{child.kill();reject(new Error('The computer certificate could not be created.'));},30000);
        child.on('error',()=>{clearTimeout(timer);reject(new Error('Certificate setup needs the installed Git/OpenSSL runtime.'));});
        child.on('close',code=>{clearTimeout(timer);code===0?resolve():reject(new Error('Certificate setup did not complete.'));});
      });
      cert=await readFile(pendingCertificate);key=await readFile(temporary,'utf8');
      await writeFile(privatePath,await credentialEncryption.encrypt(key),{flag:'wx',mode:0o600});
      await rename(pendingCertificate,publicPath);
    } finally { await unlink(temporary).catch(()=>{});await unlink(pendingCertificate).catch(()=>{}); }
  }
  return {cert,key,fingerprint:new X509Certificate(cert).fingerprint256.replaceAll(':','').toLowerCase()};
}
