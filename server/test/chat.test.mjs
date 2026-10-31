import test from 'node:test';
import assert from 'node:assert/strict';
import {ChatHub} from '../src/index.mjs';
import {webcrypto} from 'node:crypto';
if(!globalThis.crypto)globalThis.crypto=webcrypto;
function harness(){
 const db=new Map();const storage={get:async k=>db.get(k),put:async(k,v)=>{db.set(k,v)},delete:async k=>db.delete(k),list:async({prefix})=>new Map([...db].filter(([k])=>k.startsWith(prefix)))};
 const hub=new ChatHub({storage});
 const call=async(method,path,body,token)=>{const headers={};if(body)headers['content-type']='application/json';if(token)headers.authorization='Bearer '+token;const r=await hub.fetch(new Request('https://example.com'+path,{method,headers,body:body?JSON.stringify(body):undefined}));return {status:r.status,data:await r.json()}};
 return {call};
}
test('mutual consent, auth and 1:1 message delivery',async()=>{
 const {call}=harness(); const a='a'.repeat(32),b='b'.repeat(32),as='c'.repeat(64),bs='d'.repeat(64),ac='A'.repeat(24),bc='B'.repeat(24);
 assert.equal((await call('POST','/v1/register',{id:a,secret:as,invite_code:ac,name:'Alice'})).status,201);
 assert.equal((await call('POST','/v1/register',{id:b,secret:bs,invite_code:bc,name:'Bob'})).status,201);
 assert.equal((await call('GET','/v1/contacts')).status,401);
 assert.equal((await call('POST','/v1/messages',{recipient_id:b,client_id:'1'.repeat(36),text:'hack'},a+'.'+as)).status,403);
 assert.equal((await call('POST','/v1/invites',{code:bc},a+'.'+as)).status,200);
 let pending=await call('GET','/v1/contacts',undefined,b+'.'+bs);
 assert.equal(pending.data.requests[0].name,'Alice');
 assert.equal((await call('POST','/v1/invites/accept',{from_id:a},b+'.'+bs)).status,200);
 const msg={recipient_id:b,client_id:'1'.repeat(36),text:'Hello Bob'};
 assert.equal((await call('POST','/v1/messages',msg,a+'.'+as)).status,201);
 assert.equal((await call('POST','/v1/messages',msg,a+'.'+as)).data.status,'already_sent');
 const history=await call('GET','/v1/messages?peer='+a,undefined,b+'.'+bs);
 assert.equal(history.data.messages.length,1);
 assert.equal(history.data.messages[0].text,'Hello Bob');
 assert.equal((await call('GET','/v1/messages?peer='+a,undefined,'e'.repeat(32)+'.'+bs)).status,401);
});

test('unique usernames, case-insensitive search, consent and 1:1 delivery by handle', async () => {
 const {call}=harness();
 const a='1'.repeat(32),b='2'.repeat(32),c='3'.repeat(32);
 const as='a'.repeat(64),bs='b'.repeat(64),cs='c'.repeat(64);
 const ac='A'.repeat(24),bc='B'.repeat(24),cc='C'.repeat(24);
 assert.equal((await call('POST','/v1/register',{id:a,secret:as,invite_code:ac,name:'Alice',username:'Alice_Spy'})).status,201);
 assert.equal((await call('POST','/v1/register',{id:b,secret:bs,invite_code:bc,name:'Bob',username:'bob_spy'})).status,201);
 assert.equal((await call('POST','/v1/register',{id:c,secret:cs,invite_code:cc,name:'Clone',username:'ALICE_SPY'})).status,409);
 assert.equal((await call('POST','/v1/register',{id:c,secret:cs,invite_code:cc,name:'Clone',username:'admin'})).status,400);
 assert.equal((await call('GET','/v1/users/search?q=ali',undefined,b+'.'+bs)).data.users[0].username,'alice_spy');
 assert.equal((await call('GET','/v1/users/search?q=ali')).status,401);
 assert.equal((await call('POST','/v1/invites',{username:'@Alice_Spy'},b+'.'+bs)).data.status,'pending');
 assert.equal((await call('POST','/v1/messages',{recipient_id:a,client_id:'1'.repeat(36),text:'before acceptance'},b+'.'+bs)).status,403);
 assert.equal((await call('POST','/v1/invites/accept',{from_id:b},a+'.'+as)).status,200);
 assert.equal((await call('POST','/v1/messages',{recipient_id:a,client_id:'1'.repeat(36),text:'hi alice'},b+'.'+bs)).status,201);
 assert.equal((await call('GET','/v1/messages?peer='+b,undefined,a+'.'+as)).data.messages[0].text,'hi alice');
 assert.equal((await call('POST','/v1/profile/username',{username:'alice_new'},a+'.'+as)).status,200);
 assert.equal((await call('GET','/v1/users/search?q=alice_',undefined,b+'.'+bs)).data.users[0].username,'alice_new');
 assert.equal((await call('GET','/v1/users/search?q=alice_spy',undefined,b+'.'+bs)).data.users.length,0);
 assert.equal((await call('POST','/v1/profile/username',{username:'BOB_SPY'},a+'.'+as)).status,409);
});

test('old chat profile can claim username without losing contacts', async () => {
 const {call}=harness();const a='4'.repeat(32),s='f'.repeat(64),code='D'.repeat(24);
 assert.equal((await call('POST','/v1/register',{id:a,secret:s,invite_code:code,name:'Old'})).status,201);
 assert.equal((await call('POST','/v1/profile/username',{username:'new_profile'},a+'.'+s)).status,200);
 assert.equal((await call('GET','/v1/me',undefined,a+'.'+s)).data.username,'new_profile');
});
