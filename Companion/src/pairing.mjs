import { randomBytes, randomUUID, createHash, timingSafeEqual } from 'node:crypto';

const hash = value => createHash('sha256').update(value).digest('hex');

export class Pairing {
  constructor(store, vault) {
    this.store = store; this.vault = vault; this.pending = null;
    store.db.exec('CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY, token_hash TEXT NOT NULL, revoked INTEGER NOT NULL DEFAULT 0, metadata BLOB NOT NULL)');
  }
  issue({baseURL, fingerprint, serverId}) {
    const code = randomBytes(24).toString('base64url');
    this.pending = {hash:hash(code), expires:Date.now()+5*60*1000, baseURL, fingerprint, serverId};
    return {version:1, base_url:baseURL, certificate_sha256:fingerprint, server_id:serverId, pairing_code:code, expires_at:this.pending.expires};
  }
  redeem(code, name) {
    if (typeof code !== 'string' || code.length > 200 || !this.pending || this.pending.expires < Date.now()) throw Object.assign(new Error('Create a fresh pairing code on your computer.'), {status:403});
    if (!timingSafeEqual(Buffer.from(hash(code)),Buffer.from(this.pending.hash))) throw Object.assign(new Error('The pairing code did not match.'), {status:403});
    this.pending = null;
    const id = randomUUID(), credential = randomBytes(32).toString('base64url');
    const metadata = {name:String(name ?? 'iPhone').slice(0,80), created_at:Date.now()};
    this.store.db.prepare('INSERT INTO devices(id,token_hash,metadata) VALUES(?,?,?)').run(id,hash(credential),this.vault.sealJSON(metadata,'device:'+id));
    return {device_id:id, credential};
  }
  authenticate(header) {
    if (typeof header !== 'string' || !header.startsWith('Bearer ') || header.length > 200) throw Object.assign(new Error('Connect this device to the computer first.'), {status:401});
    const tokenHash = hash(header.slice(7));
    const row = this.store.db.prepare('SELECT id FROM devices WHERE token_hash=? AND revoked=0').get(tokenHash);
    if (!row) throw Object.assign(new Error('This device connection is no longer active.'), {status:401});
    return row.id;
  }
  devices() {
    return this.store.db.prepare('SELECT id,metadata FROM devices WHERE revoked=0').all().map(row=>({id:row.id,...this.vault.openJSON(row.metadata,'device:'+row.id)}));
  }
  revoke(id) { this.store.db.prepare('UPDATE devices SET revoked=1 WHERE id=?').run(id); }
}
