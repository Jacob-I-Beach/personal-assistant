// Optional computation health must never gate account, catalog or job access.
export class ServiceReadiness {
  constructor(check,{ttl=30000,timeout=3000,now=Date.now}={}){this.check=check;this.ttl=ttl;this.timeout=timeout;this.now=now;this.value=null;this.checkedAt=null;this.pending=null;this.closed=false;}
  snapshot(){
    if(!this.closed&&!this.pending&&(this.checkedAt===null||this.now()-this.checkedAt>=this.ttl))this.refresh();
    return {state:this.pending?'checking':this.value===true?'ready':'unavailable',available:this.value,checked_at:this.checkedAt===null?null:new Date(this.checkedAt).toISOString()};
  }
  refresh(){
    const controller=new AbortController();this.controller=controller;
    let timer;
    const timed=new Promise(resolve=>{timer=setTimeout(()=>{controller.abort();resolve(false);},this.timeout);timer.unref?.();});
    this.pending=Promise.race([Promise.resolve().then(()=>this.check(controller.signal)).catch(()=>false),timed]).then(value=>{
      this.value=value===true;this.checkedAt=this.now();
    }).finally(()=>{clearTimeout(timer);this.pending=null;});
  }
  close(){this.closed=true;this.controller?.abort();}
}
