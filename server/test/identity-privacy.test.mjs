import test from 'node:test';
import assert from 'node:assert/strict';
import {setup,id,code} from './helpers/conversation-harness.mjs';
const avatar=accent=>({version:1,style:'web',accent,seed:'f'.repeat(32)});

test('Public is searchable; Private removes search and permits invitation codes',async()=>{
 const {call}=await setup();
 assert.equal((await call('/v1/users/search?q=user_b',undefined,'c')).body.users.length,1);
 assert.equal((await call('/v4/profile/privacy',{mode:'private'},'b')).body.discoverable,false);
 assert.equal((await call('/v1/users/search?q=user_b',undefined,'c')).body.users.length,0);
 assert.equal((await call('/v3/contacts/connect',{username:'user_b'},'c')).status,404);
 assert.equal((await call('/v3/contacts/connect',{code:code('b')},'c')).body.status,'connected');
});
test('Hidden blocks new codes and usernames while retaining existing chats and keys',async()=>{
 const {call,send,history}=await setup();
 await call('/v4/profile/privacy',{mode:'hidden'},'b');
 assert.equal((await call('/v3/contacts/connect',{code:code('b')},'c')).status,403);
 assert.equal((await call('/v3/contacts/connect',{username:'user_b'},'c')).status,404);
 assert.equal((await call('/v1/users/search?q=user_b',undefined,'c')).body.users.length,0);
 assert.equal((await send()).status,201);assert.equal((await history('b','a')).length,1);
 assert.equal((await call('/v2/keys?peer='+id('b'))).status,200);
 await call('/v4/profile/privacy',{mode:'private'},'b');
 assert.equal((await call('/v3/contacts/connect',{code:code('b')},'c')).body.status,'connected');
});
test('legacy privacy toggles cannot silently undo Hidden; editing profile preserves it',async()=>{
 const {call}=await setup();await call('/v4/profile/privacy',{mode:'hidden'},'b');
 assert.equal((await call('/v2/profile/privacy',{discoverable:true},'b')).status,409);
 assert.equal((await call('/v2/profile/privacy',{discoverable:false},'b')).status,409);
 await call('/v3/profile',{bio:'Bio',status:'Quiet',avatar:avatar('gold')},'b');
 await call('/v2/profile/name',{name:'Hidden identity'},'b');
 await call('/v1/profile/username',{username:'renamed_b'},'b');
 assert.equal((await call('/v4/profile/privacy',undefined,'b')).body.mode,'hidden');
 assert.equal((await call('/v1/users/search?q=renamed',undefined,'c')).body.users.length,0);
});
test('reserving a handle does not make an invite-only identity public without explicit selection',async()=>{
 const {call}=await setup();
 assert.equal((await call('/v1/register',{id:id('d'),secret:'d'.repeat(64),invite_code:code('d'),name:'Private'})).status,201);
 assert.equal((await call('/v4/profile/privacy',{mode:'public'},'d')).status,409);
 assert.equal((await call('/v1/profile/username',{username:'private_d'},'d')).status,200);
 assert.equal((await call('/v1/users/search?q=private',undefined,'c')).body.users.length,0);
 assert.equal((await call('/v4/profile/privacy',{mode:'public'},'d')).status,200);
 assert.equal((await call('/v1/users/search?q=private',undefined,'c')).body.users[0].id,id('d'));
});
test('privacy updates require authentication and only affect the owning persona',async()=>{
 const {call}=await setup();
 assert.equal((await call('/v4/profile/privacy',{mode:'hidden'},'e')).status,401);
 assert.equal((await call('/v4/profile/privacy',{mode:'ghost'},'a')).status,400);
 await call('/v4/profile/privacy',{mode:'hidden'},'a');
 assert.equal((await call('/v4/profile/privacy',undefined,'b')).body.mode,'public');
 assert.equal((await call('/v4/profile/privacy',undefined,'a')).body.mode,'hidden');
});
test('all eleven persona palette colors and existing legacy colors round-trip through server validation',async()=>{
 const {call}=await setup();
 for(const accent of ['gold','blue','violet','emerald','cyan','red','magenta','silver','amber','copper','white',
  'lime','orange','ice','pink','ultraviolet']){
  const result=await call('/v3/profile',{bio:'',status:'',avatar:avatar(accent)});
  assert.equal(result.status,200,accent);assert.equal(result.body.avatar.accent,accent);
 }
 assert.equal((await call('/v3/profile',{bio:'',status:'',avatar:avatar('unknown')})).status,400);
});
test('a delayed profile request authenticated before Hidden cannot overwrite the newer privacy setting',async()=>{
 const {call,hub}=await setup();
 const readBody=hub.body.bind(hub);
 let release,arrived;
 const gate=new Promise(resolve=>{release=resolve;});
 const paused=new Promise(resolve=>{arrived=resolve;});
 hub.body=async request=>{
  if(new URL(request.url).pathname==='/v3/profile'){arrived();await gate;}
  return readBody(request);
 };
 const editing=call('/v3/profile',{bio:'Delayed edit',status:'',avatar:avatar('white')},'b');
 await paused;await call('/v4/profile/privacy',{mode:'hidden'},'b');release();
 assert.equal((await editing).status,200);
 assert.equal((await call('/v4/profile/privacy',undefined,'b')).body.mode,'hidden');
});
test('Hidden still allows an explicit outgoing connection and discards old pending incoming invites',async()=>{
 const {call,db}=await setup();await call('/v4/profile/privacy',{mode:'hidden'},'b');
 db.set('invite:'+id('b')+':'+id('c'),{from:id('c'),to:id('b'),status:'pending'});
 const contacts=await call('/v1/contacts',undefined,'b');
 assert.equal(contacts.body.contacts.length,1);
 assert.equal(db.has('invite:'+id('b')+':'+id('c')),false);
 assert.equal((await call('/v3/contacts/connect',{username:'user_c'},'b')).body.status,'connected');
 assert.equal((await call('/v4/profile/privacy',undefined,'b')).body.mode,'hidden');
});
