import test from 'node:test';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {ChatHub} from '../src/chat.mjs';
if(!globalThis.crypto)globalThis.crypto=webcrypto;

async function setup() {
 const db=new Map();
 const makeStorage=map=>({get:async k=>map.get(k),put:async(k,v)=>map.set(k,structuredClone(v)),
   delete:async k=>map.delete(k),list:async({prefix})=>new Map([...map].filter(([k])=>k.startsWith(prefix)))});
 const storage=makeStorage(db);
 storage.transaction=async fn=>{
   const staged=new Map(structuredClone([...db]));
   const value=await fn(makeStorage(staged));
   db.clear();for(const [k,v] of staged)db.set(k,v);
   return value;
 };
 const hub=new ChatHub({storage});const pushes=[];hub.queuePush=(id,event)=>pushes.push({id,event});
 const id=n=>n.repeat(32),auth=n=>id(n)+'.'+n.repeat(64);
 const call=async(path,body,who='a',method='POST')=>{
  const response=await hub.fetch(new Request('https://test'+path,{method,
   headers:{authorization:'Bearer '+auth(who),'content-type':'application/json'},
   body:method==='GET'?undefined:JSON.stringify(body)}));
  return {status:response.status,body:await response.json()};
 };
 for(const n of ['a','b','c'])assert.equal((await call('/v1/register',{
  id:id(n),secret:n.repeat(64),invite_code:n.toUpperCase().repeat(24),name:n,
  username:'user_'+n,discoverable:n!=='c'
 },n)).status,201);
 return {db,call,pushes,id,hub};
}

test('instant username connection creates both contact lists and key access without accept',async()=>{
 const {call,id,pushes}=await setup();
 const result=await call('/v3/contacts/connect',{username:'user_b'});
 assert.equal(result.body.status,'connected');assert.equal(result.body.peer.id,id('b'));
 for(const [who,peer] of [['a','b'],['b','a']]){
  const list=await call('/v1/contacts',null,who,'GET');
  assert.deepEqual(list.body.requests,[]);assert.equal(list.body.contacts[0].id,id(peer));
 }
 assert.equal(pushes.length,1);
 assert.equal((await call('/v3/contacts/connect',{username:'user_b'})).body.status,'already_connected');
 assert.equal(pushes.length,1);
 const history=await call('/v3/invites/history',null,'b','GET');
 assert.equal(history.body.events.length,1);assert.equal(history.body.events[0].direction,'incoming');
});
test('private recipient requires capability code; limit unknown blocks username but permits code',async()=>{
 const {call}=await setup();
 assert.equal((await call('/v3/contacts/connect',{username:'user_c'})).status,404);
 assert.equal((await call('/v3/contacts/privacy',{limit_unknown:true},'b')).status,200);
 assert.equal((await call('/v3/contacts/connect',{username:'user_b'})).status,403);
 assert.equal((await call('/v3/contacts/connect',{code:'B'.repeat(24)})).body.status,'connected');
 assert.equal((await call('/v3/contacts/connect',{code:'C'.repeat(24)})).body.status,'connected');
});
test('blocked contact cannot reconnect by code or username in either direction',async()=>{
 const {call}=await setup();await call('/v3/contacts/connect',{username:'user_b'});
 await call('/v2/contacts/block',{peer_id:'b'.repeat(32)});
 for(const [who,body] of [['a',{code:'B'.repeat(24)}],['b',{code:'A'.repeat(24)}],['a',{username:'user_b'}]]){
  assert.equal((await call('/v3/contacts/connect',body,who)).status,403);
 }
 assert.equal((await call('/v1/contacts',null,'b','GET')).body.contacts.length,0);
});
test('legacy pending migration respects blocks and unknown policy and does not recreate requests',async()=>{
 const {call,db,id}=await setup();
 db.set('invite:'+id('b')+':'+id('a'),{from:id('a'),to:id('b'),status:'pending'});
 let list=await call('/v1/contacts',null,'b','GET');
 assert.equal(list.body.contacts[0].id,id('a'));assert.deepEqual(list.body.requests,[]);
 db.set('invite:'+id('c')+':'+id('a'),{from:id('a'),to:id('c'),status:'pending'});
 await call('/v3/contacts/privacy',{limit_unknown:true},'c');
 list=await call('/v1/contacts',null,'c','GET');
 assert.deepEqual(list.body.contacts,[]);assert.deepEqual(list.body.requests,[]);
 assert.equal(db.has('invite:'+id('c')+':'+id('a')),false);
});
test('authenticated privacy/history and invalid lookup never create contacts',async()=>{
 const {call,db}=await setup();
 assert.equal((await call('/v3/contacts/privacy',{limit_unknown:'true'})).status,400);
 assert.equal((await call('/v3/contacts/connect',{code:'invalid'})).status,400);
 assert.equal((await call('/v3/contacts/connect',{username:'user_a'})).status,404);
 assert.equal((await call('/v3/contacts/connect',{code:'B'.repeat(24)},'d')).status,401);
 assert.equal((await call('/v3/invites/history',null,'d','GET')).status,401);
 assert.equal([...db.keys()].some(k=>k.startsWith('contact:')),false);
});
test('legacy invite and accept remain idempotent with instant connection',async()=>{
 const {call,id}=await setup();
 assert.equal((await call('/v1/invites',{code:'B'.repeat(24)})).body.status,'connected');
 assert.equal((await call('/v1/invites/accept',{from_id:id('a')},'b')).body.status,'connected');
 assert.equal((await call('/v3/invites/history',null,'a','GET')).body.events.length,1);
});
test('mute is enforced by notification delivery and hide preferences are private to owner',async()=>{
 const {call,id,hub,db}=await setup();
 assert.equal((await call('/v3/contacts/preferences',{peer_id:id('b'),muted:true,hidden:true})).status,403);
 await call('/v3/contacts/connect',{username:'user_b'});
 assert.equal((await call('/v3/contacts/preferences',{peer_id:id('b'),muted:true,hidden:true})).status,200);
 assert.deepEqual((await call('/v1/contacts',null,'a','GET')).body.preferences[id('b')],{muted:true,hidden:true});
 assert.deepEqual((await call('/v1/contacts',null,'b','GET')).body.preferences[id('a')],{muted:false,hidden:false});
 // Muted delivery must stop before reading APNs token/provider credentials.
 db.set('push:'+id('a'),{token:'not-a-real-token',enabled:true});
 await hub.notify(id('a'),'message',id('b'));
 assert.equal(db.has('pushlast:'+id('a')),false);
 assert.equal((await call('/v3/contacts/preferences',{peer_id:id('b'),muted:'yes',hidden:false})).status,400);
});
test('failed connection transaction leaves neither half contact nor history',async()=>{
 const {hub,db,id}=await setup();
 const original=hub.ctx.storage.transaction;
 hub.ctx.storage.transaction=async fn=>original(async tx=>{
  const put=tx.put;
  tx.put=async(k,v)=>{if(k==='contact:'+id('b')+':'+id('a'))throw new Error('storage fault');return put(k,v);};
  return fn(tx);
 });
 await assert.rejects(()=>hub.connectPeople(id('a'),id('b'),'code'),/storage fault/);
 assert.equal([...db.keys()].some(k=>k.startsWith('contact:')||k.startsWith('link:')||k.startsWith('invitehistory:')),false);
});
