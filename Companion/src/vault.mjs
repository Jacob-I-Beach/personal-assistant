import { spawn } from 'node:child_process';
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const protector = fileURLToPath(new URL('../scripts/protect-data.ps1', import.meta.url));

async function protectedData(operation, value) {
  if (process.platform !== 'win32') throw new Error('This package requires Windows protected storage.');
  const executable = join(process.env.SystemRoot ?? 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
  return new Promise((resolve, reject) => {
    const child = spawn(executable, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', protector, '-Operation', operation], { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    let output = '', length = 0;
    const timer = setTimeout(() => { child.kill(); reject(new Error('Windows protected storage did not respond.')); }, 15000);
    child.stdout.on('data', part => { length += part.length; if (length > 2 * 1024 * 1024) child.kill(); else output += part; });
    child.stderr.resume();
    child.on('error', () => { clearTimeout(timer); reject(new Error('Windows protected storage could not start.')); });
    child.on('close', code => {
      clearTimeout(timer);
      if (code !== 0 || length > 2 * 1024 * 1024) reject(new Error('Windows could not unlock the companion’s protected data.'));
      else resolve(Buffer.from(output.trim(), 'base64'));
    });
    child.stdin.end(Buffer.from(value).toString('base64'));
  });
}

export const credentialEncryption = {
  id: 'personal-assistant-windows-dpapi-v1',
  isAvailable: () => process.platform === 'win32',
  encrypt: text => protectedData('protect', Buffer.from(text, 'utf8')),
  decrypt: async bytes => (await protectedData('unprotect', bytes)).toString('utf8')
};

export class Vault {
  constructor(key) {
    if (!Buffer.isBuffer(key) || key.length !== 32) throw new Error('Invalid vault key.');
    this.key = Buffer.from(key);
  }
  static async open(root) {
    const path = join(root, 'work-key.protected');
    await mkdir(dirname(path), {recursive: true});
    try { return new Vault(await protectedData('unprotect', await readFile(path))); }
    catch (error) {
      if (error.code !== 'ENOENT') throw error;
      const key = randomBytes(32);
      await writeFile(path, await protectedData('protect', key), {flag: 'wx', mode: 0o600});
      return new Vault(key);
    }
  }
  seal(value, purpose) {
    const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', this.key, iv);
    cipher.setAAD(Buffer.from(purpose, 'utf8'));
    const encrypted = Buffer.concat([cipher.update(Buffer.from(value)), cipher.final()]);
    return Buffer.concat([Buffer.from('PAC1'), iv, cipher.getAuthTag(), encrypted]);
  }
  open(value, purpose) {
    const bytes = Buffer.from(value);
    if (bytes.length < 32 || bytes.subarray(0, 4).toString() !== 'PAC1') throw new Error('Invalid saved-work record.');
    const decipher = createDecipheriv('aes-256-gcm', this.key, bytes.subarray(4, 16));
    decipher.setAAD(Buffer.from(purpose, 'utf8')); decipher.setAuthTag(bytes.subarray(16, 32));
    return Buffer.concat([decipher.update(bytes.subarray(32)), decipher.final()]);
  }
  sealJSON(value, purpose) { return this.seal(Buffer.from(JSON.stringify(value)), purpose); }
  openJSON(value, purpose) { return JSON.parse(this.open(value, purpose).toString('utf8')); }
}
