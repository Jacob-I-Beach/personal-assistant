// Account-scoped, encrypted last-known model choices. Sign-in, reachability and
// catalog freshness are separate facts. Never invent account entitlements.
export class ModelCatalog {
  constructor(store,provider,{now=Date.now,ttl=300000,retryDelay=15000}={}) {
    this.store=store;this.provider=provider;this.now=now;this.ttl=ttl;this.retryDelay=retryDelay;
    this.pending=new Map();this.failures=new Map();
    store.db.exec('CREATE TABLE IF NOT EXISTS model_catalogs(profile TEXT PRIMARY KEY,data BLOB NOT NULL)');
  }
  snapshot(profileId) {
    let saved=null;
    if(profileId){const row=this.store.db.prepare('SELECT data FROM model_catalogs WHERE profile=?').get(profileId);if(row)saved=this.store.vault.openJSON(row.data,'model-catalog:'+profileId);}
    const failure=this.failures.get(profileId);
    const stale=!!saved&&(!!failure||this.now()-saved.updatedAt>this.ttl);
    return {profile_id:profileId??null,models:saved?.models??[],catalog:{state:saved?(stale?'stale':'ready'):'unavailable',
      updated_at:saved?new Date(saved.updatedAt).toISOString():null,
      ...(failure?{error:failure.message,http_status:failure.status}:{}),
      ...(stale&&!failure?{error:'Showing saved model choices. Refresh to check current availability.'}:{})}};
  }
  async load({force=false}={}) {
    const session=await this.provider.getSession(),profile=session.profileId;
    if(session.status!=='connected'||!session.sharing||!profile)return {profile_id:profile??null,models:[],catalog:{state:'unavailable',error:'Connect ChatGPT and enable plan sharing to load models.'}};
    if(this.pending.has(profile))return this.pending.get(profile);
    const snapshot=this.snapshot(profile),failure=this.failures.get(profile);
    if(!force&&(snapshot.catalog.state==='ready'||failure&&this.now()-failure.at<this.retryDelay))return snapshot;
    const pending=this.refresh(profile).finally(()=>this.pending.delete(profile));this.pending.set(profile,pending);return pending;
  }
  async refresh(profile) {
    try {
      const models=await this.provider.listModels({signal:AbortSignal.timeout(15000)});
      if(!Array.isArray(models)||models.some(item=>typeof item.slug!=='string'||typeof item.displayName!=='string'))throw new Error('The model catalog response was not valid.');
      const current=await this.provider.getSession();
      if(current.profileId!==profile||current.status!=='connected'||!current.sharing)throw Object.assign(new Error('The ChatGPT account changed during refresh.'),{code:'account_changed'});
      const seen=new Set(),unique=models.filter(model=>!seen.has(model.slug)&&seen.add(model.slug));
      const data={models:unique,updatedAt:this.now()};
      this.store.db.prepare('INSERT INTO model_catalogs(profile,data) VALUES(?,?) ON CONFLICT(profile) DO UPDATE SET data=excluded.data').run(profile,this.store.vault.sealJSON(data,'model-catalog:'+profile));
      this.failures.delete(profile);
    }catch(error){
      // Avoid leaking raw provider bodies or credentials into app/HTML notices.
      const status=Number.isInteger(error.status)?error.status:null;
      const message=error.code==='account_changed'?'The ChatGPT account changed. Refresh its model list.':
        status?`ChatGPT model discovery returned HTTP ${status}. Your sign-in is saved; current model availability could not be checked.`:
        'ChatGPT model discovery is unavailable. Your sign-in is saved; try refreshing the model list.';
      this.failures.set(profile,{at:this.now(),status,message});
    }
    return this.snapshot(profile);
  }
}
