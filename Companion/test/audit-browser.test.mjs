import test from 'node:test';
import assert from 'node:assert/strict';
import {BrowserRuntime} from '../src/browser-runtime.mjs';

test('one task cannot interleave browser actions while its first action is pending',async()=>{
  let released;const waiting=new Promise(r=>{released=r;}),abort=new AbortController();
  const runtime=new BrowserRuntime({store:{},review:async()=>{},launch:async()=>{await waiting;return {close:async()=>{},newContext:async()=>{throw new Error('No page should be created after stop');}};}});
  const first=runtime.execute({arguments:{action:'snapshot'}},{id:'same-task'},abort.signal);
  const second=runtime.execute({arguments:{action:'open',url:'https://example.test'}},{id:'same-task'},new AbortController().signal);
  const rejected=assert.rejects(second,/already in progress/);
  abort.abort(new Error('Stopped'));released();
  await assert.rejects(first,/Stopped/);await rejected;
  assert.equal(runtime.executing.size,0);await runtime.close();
});

test('partial browser acquisition closes resources and never admits navigation after cancellation',async()=>{
  for(const stage of ['before','launch','context','page','context-failure','page-failure']){
    let closed=0,navigated=0,launched=0;const abort=new AbortController();
    if(stage==='before')abort.abort(new Error('Stopped'));
    const page={setDefaultTimeout(){},goto(){navigated++;}};
    const browser=new BrowserRuntime({store:{},review:async()=>{},launch:async()=>{
      launched++;if(stage==='launch')abort.abort(new Error('Stopped'));
      return {close:async()=>{closed++;},newContext:async()=>{
        if(stage==='context-failure')throw new Error('Context failed');
        if(stage==='context')abort.abort(new Error('Stopped'));
        return {newPage:async()=>{if(stage==='page-failure')throw new Error('Page failed');if(stage==='page')abort.abort(new Error('Stopped'));return page;}};
      }};
    }});
    await assert.rejects(browser.execute({arguments:{action:'open',url:'https://example.test'}},{id:'task'},abort.signal));
    assert.equal(navigated,0);assert.equal(closed,launched);assert.equal(browser.sessions.size,0);assert.equal(browser.pending.size,0);
  }
});

test('simultaneous first browser calls share one acquisition and close waits for it',async()=>{
  let released,launched=0,closed=0;const waiting=new Promise(r=>{released=r;});
  const browser=new BrowserRuntime({store:{},review:async()=>{},launch:async()=>{launched++;await waiting;return {close:async()=>{closed++;},newContext:async()=>({newPage:async()=>({setDefaultTimeout(){}})})};}});
  const a=browser.session({id:'task'}),b=browser.session({id:'task'});
  const closing=browser.close('task');released();
  assert.equal(await a,await b);await closing;
  assert.equal(launched,1);assert.equal(closed,1);assert.equal(browser.sessions.size,0);
});

test('actual Edge DOM review rejects changed targets and accepts one stable fill',async()=>{
  let mutate=async()=>{},saved=0;
  const runtime=new BrowserRuntime({store:{saveFile:(_job,_meta,bytes)=>{assert.equal(bytes.subarray(1,4).toString(),'PNG');saved++;return {id:'fixture',filename:'fixture.png'};}},review:async()=>mutate()});
  const job={id:'browser-audit',payload:{}},signal=new AbortController().signal;
  try {
    const state=await runtime.session(job);
    for(const mutation of ['password','disabled','replacement','form-action','form-method','href','stable']){
      await state.page.setContent('<title>Synthetic review fixture</title><form action="http://127.0.0.1/approved" method="get"><input aria-label="Example" type="text"><button type="submit">Send</button></form><a href="http://127.0.0.1/approved">Link</a>');
      const snapshot=await runtime.execute({id:'observe-'+mutation,arguments:{action:'snapshot'}},job,signal);
      const link=mutation==='href',control=snapshot.output.controls.find(c=>c.name===(link?'Link':'Example'));
      mutate=async()=>state.page.evaluate(kind=>{
        const input=document.querySelector('input'),form=document.querySelector('form');
        if(kind==='password')input.type='password';
        if(kind==='disabled')input.disabled=true;
        if(kind==='replacement')input.replaceWith(input.cloneNode(true));
        if(kind==='form-action')form.action='http://127.0.0.1/changed';
        if(kind==='form-method')form.method='post';
        if(kind==='href')document.querySelector('a').href='http://127.0.0.1/changed';
      },mutation);
      const action=runtime.execute({id:'act-'+mutation,arguments:{action:link?'click':'fill',observation_id:snapshot.output.observation_id,element_id:control.element_id,text:'Synthetic text',reason:'Fixture review'}},job,signal);
      if(mutation==='stable'){assert.equal((await action).succeeded,true);assert.equal(await state.page.locator('input').inputValue(),'Synthetic text');}
      else {await assert.rejects(action,/page changed/);assert.equal(await state.page.locator('input').inputValue(),'');}
    }
    assert.ok(saved>=8);
  }finally{await runtime.close();}
});

test('browser workspaces have a resource ceiling and idle expiry without interrupting active work',async()=>{
  let time=1000,closed=0;
  const runtime=new BrowserRuntime({store:{},review:async()=>{},now:()=>time,idleMilliseconds:100,maximumSessions:2,launch:async()=>({close:async()=>{closed++;},newContext:async()=>({newPage:async()=>({setDefaultTimeout(){}})})})});
  try{
    await runtime.session({id:'a'});await runtime.session({id:'b'});
    await assert.rejects(runtime.session({id:'c'}),/active task workspaces/);
    runtime.executing.add('a');time=1200;await runtime.reapIdle();
    assert.equal(runtime.sessions.has('a'),true);assert.equal(runtime.sessions.has('b'),false);assert.equal(closed,1);
    await runtime.session({id:'c'});runtime.executing.delete('a');await runtime.reapIdle();
    assert.equal(runtime.sessions.has('a'),false);assert.equal(runtime.sessions.has('c'),true);
  }finally{await runtime.close();}
  assert.equal(closed,3);
});
