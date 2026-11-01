import test from 'node:test';
import assert from 'node:assert/strict';
import {ChatHub} from '../src/index.mjs';
import {webcrypto} from 'node:crypto';
if(!globalThis.crypto)globalThis.crypto=webcrypto;

function harness(){
 const db=new Map();
 const storage={get:async k=>db.get(k),put:async(k,v)=>{db.set(k,v)},delete:async k=>db.delete(k),
   list:async({prefix})=>new Map([...db].filter(([k])=>k.startsWith(prefix)))};
 const hub=new ChatHub({storage});
 const call=async(method,path,body,token)=>{
   const headers={};if(body)headers['content-type']='application/json';if(token)headers.authorization='Bearer '+token;
   const response=await hub.fetch(new Request('https://example.com'+path,{method,headers,body:body?JSON.stringify(body):undefined}));
   return {status:response.status,data:await response.json()};
 };
 return {call,db};
}
const key=(char='A')=>({version:2,key_agreement:Buffer.alloc(32,char).toString('base64'),signature:Buffer.alloc(32,char).toString('base64')});
const ids={a:'a'.repeat(32),b:'b'.repeat(32),c:'c'.repeat(32),as:'d'.repeat(64),bs:'e'.repeat(64),cs:'f'.repeat(64),ac:'A'.repeat(24),bc:'B'.repeat(24),cc:'C'.repeat(24)};
const auth=(id,secret)=>id+'.'+secret;
const envelope=(recipient_id,client_id='1'.repeat(36))=>({recipient_id,client_id,
 ephemeral_key:key('C').key_agreement,recipient_box:Buffer.alloc(52,'X').toString('base64'),
 sender_box:Buffer.alloc(52,'Y').toString('base64'),signature:Buffer.alloc(64,'Z').toString('base64')});
async function registerPair(call){
 assert.equal((await call('POST','/v1/register',{id:ids.a,secret:ids.as,invite_code:ids.ac,name:'Alice',username:'alice_user',keys:key('A')})).status,201);
 assert.equal((await call('POST','/v1/register',{id:ids.b,secret:ids.bs,invite_code:ids.bc,name:'Bob',username:'bob_user',keys:key('B')})).status,201);
}
async function connect(call){
 assert.equal((await call('POST','/v2/profile/privacy',{discoverable:true},auth(ids.b,ids.bs))).status,200);
 assert.equal((await call('POST','/v1/invites',{username:'bob_user'},auth(ids.a,ids.as))).status,200);
 assert.equal((await call('POST','/v1/invites/accept',{from_id:ids.a},auth(ids.b,ids.bs))).status,200);
}

test('protocol v2 requires contact authorization and never writes new plaintext',async()=>{
 const {call,db}=harness(); await registerPair(call);
 assert.deepEqual((await call('GET','/health')).data,{status:'ok',service:'spyder-chat-devnet',version:2,e2ee:true});
 assert.equal((await call('GET','/v1/contacts')).status,401);
 assert.equal((await call('POST','/v1/messages',{recipient_id:ids.b,client_id:'1'.repeat(36),text:'secret'},auth(ids.a,ids.as))).status,410);
 assert.equal((await call('POST','/v2/messages',envelope(ids.b),auth(ids.a,ids.as))).status,403);
 assert.equal((await call('GET','/v2/keys?peer='+ids.b,undefined,auth(ids.a,ids.as))).status,403);
 assert.equal((await call('POST','/v2/profile/privacy',{discoverable:true},auth(ids.b,ids.bs))).status,200);
 await connect(call);
 assert.deepEqual((await call('GET','/v2/keys?peer='+ids.b,undefined,auth(ids.a,ids.as))).data.keys,key('B'));
 assert.equal((await call('POST','/v2/messages',{...envelope(ids.b),text:'accidental plaintext'},auth(ids.a,ids.as))).status,400);
 assert.equal((await call('POST','/v2/messages',envelope(ids.b),auth(ids.a,ids.as))).status,201);
 assert.equal((await call('POST','/v2/messages',envelope(ids.b),auth(ids.a,ids.as))).data.status,'already_sent');
 const result=await call('GET','/v2/messages?peer='+ids.a,undefined,auth(ids.b,ids.bs));
 assert.equal(result.data.messages.length,1);
 assert.equal(result.data.messages[0].sender_id,ids.a);
 assert.equal(result.data.messages[0].text,undefined);
 assert.equal([...db].some(([k,v])=>k.startsWith('msgs:') && JSON.stringify(v).includes('secret')),false);
 assert.equal((await call('GET','/v2/messages?peer='+ids.b,undefined,auth(ids.c,ids.cs))).status,401);
});

test('key registration immutable and legacy account can activate encryption once',async()=>{
 const {call}=harness();
 assert.equal((await call('POST','/v1/register',{id:ids.a,secret:ids.as,invite_code:ids.ac,name:'Alice'})).status,201);
 assert.equal((await call('POST','/v2/keys/activate',key('A'),auth(ids.a,ids.as))).data.status,'active');
 assert.equal((await call('POST','/v2/keys/activate',key('A'),auth(ids.a,ids.as))).data.status,'already_active');
 assert.equal((await call('POST','/v2/keys/activate',key('B'),auth(ids.a,ids.as))).status,409);
 assert.equal((await call('POST','/v2/keys/activate',{...key('A'),version:1},auth(ids.a,ids.as))).status,400);
 assert.equal((await call('POST','/v1/register',{id:ids.b,secret:ids.bs,invite_code:ids.bc,name:'bad',keys:{version:2,signature:'x'}})).status,400);
});

test('blocking revokes contact access and rejects repeat invitations',async()=>{
 const {call}=harness();await registerPair(call); await connect(call);
 assert.equal((await call('POST','/v2/contacts/block',{peer_id:ids.b},auth(ids.a,ids.as))).data.status,'blocked');
 assert.equal((await call('GET','/v2/messages?peer='+ids.a,undefined,auth(ids.b,ids.bs))).status,403);
 assert.equal((await call('POST','/v2/messages',envelope(ids.b),auth(ids.a,ids.as))).status,403);
 assert.equal((await call('POST','/v1/invites',{code:ids.ac},auth(ids.b,ids.bs))).status,403);
 assert.equal((await call('POST','/v1/invites',{code:ids.bc},auth(ids.a,ids.as))).status,403);
});

test('unique handles cannot impersonate reserved usernames',async()=>{
 const {call}=harness();await registerPair(call);
 assert.equal((await call('POST','/v1/register',{id:ids.c,secret:ids.cs,invite_code:ids.cc,name:'Clone',username:'ALICE_USER'})).status,409);
 assert.equal((await call('POST','/v1/register',{id:ids.c,secret:ids.cs,invite_code:ids.cc,name:'Clone',username:'admin'})).status,400);
 assert.equal((await call('GET','/v1/users/search?q=alice',undefined,auth(ids.b,ids.bs))).data.users.length,0);
 assert.equal((await call('POST','/v2/profile/privacy',{discoverable:true},auth(ids.a,ids.as))).status,200);
 assert.equal((await call('GET','/v1/users/search?q=alice',undefined,auth(ids.b,ids.bs))).data.users[0].username,'alice_user');
 assert.equal((await call('POST','/v1/profile/username',{username:'alice_new'},auth(ids.a,ids.as))).status,200);
 assert.equal((await call('GET','/v1/users/search?q=alice',undefined,auth(ids.b,ids.bs))).data.users[0].username,'alice_new');
});

test('invitation rate limits prevent spam from one account',async()=>{
 const {call}=harness(); await registerPair(call);
 for(let i=0;i<15;i++){
  assert.equal((await call('POST','/v1/invites',{code:ids.bc},auth(ids.a,ids.as))).status,200);
 }
 assert.equal((await call('POST','/v1/invites',{code:ids.bc},auth(ids.a,ids.as))).status,429);
});

test('search privacy requires explicit consent; private users remain inviteable via code',async()=>{
 const {call}=harness();await registerPair(call);
 assert.equal((await call('GET','/v1/users/search?q=bob',undefined,auth(ids.a,ids.as))).data.users.length,0);
 assert.equal((await call('POST','/v1/invites',{username:'bob_user'},auth(ids.a,ids.as))).status,404);
 assert.equal((await call('POST','/v1/invites',{code:ids.bc},auth(ids.a,ids.as))).status,200);
 assert.equal((await call('POST','/v2/profile/privacy',{discoverable:true},auth(ids.b,ids.bs))).status,200);
 assert.equal((await call('GET','/v1/users/search?q=bob',undefined,auth(ids.a,ids.as))).data.users[0].username,'bob_user');
});
