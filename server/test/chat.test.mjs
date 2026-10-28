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
