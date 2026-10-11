import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {Vault} from '../src/vault.mjs';
import {JobStore} from '../src/job-store.mjs';
import {Pairing} from '../src/pairing.mjs';

test('pairing is single-use, credentials stay hashed, and revocation closes access',()=>{
  const vault=new Vault(randomBytes(32)),store=new JobStore(':memory:',vault),pairing=new Pairing(store,vault);
  const payload=pairing.issue({baseURL:'https://127.0.0.1:48681',fingerprint:'a'.repeat(64),serverId:'synthetic'});
  assert.throws(()=>pairing.redeem('wrong','phone'));
  const device=pairing.redeem(payload.pairing_code,'Synthetic iPhone');
  assert.equal(pairing.authenticate('Bearer '+device.credential),device.device_id);
  assert.throws(()=>pairing.redeem(payload.pairing_code,'phone'));
  const stored=store.db.prepare('SELECT token_hash FROM devices').get();
  assert.notEqual(stored.token_hash,device.credential);
  pairing.revoke(device.device_id);
  assert.throws(()=>pairing.authenticate('Bearer '+device.credential));
  store.close();
});
