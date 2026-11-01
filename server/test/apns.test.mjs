import test from 'node:test';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {sendAPNs,apnsConfigured} from '../src/apns.mjs';
import {ChatHub} from '../src/index.mjs';
if(!globalThis.crypto)globalThis.crypto=webcrypto;
const token='a'.repeat(64);
async function env() {
  const pair=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
  const key=Buffer.from(await crypto.subtle.exportKey('pkcs8',pair.privateKey)).toString('base64');
  return {APNS_TEAM_ID:'ABCDE12345',APNS_KEY_ID:'12345ABCDE',APNS_BUNDLE_ID:'com.spyder.wallet',
    APNS_PRIVATE_KEY:'-----BEGIN PRIVATE KEY-----\n'+key+'\n-----END PRIVATE KEY-----',
    APNS_ENVIRONMENT:'production',verifyKey:pair.publicKey};
}

test('APNs signs ES256 JWT and never leaks the message text',async()=>{
  const e=await env(); let url,options;
  const status=await sendAPNs(e,token,'message',async(u,o)=>{url=u;options=o;return {status:200}});
  assert.equal(status,200);
  assert.equal(url,'https://api.push.apple.com/3/device/'+token);
  assert.equal(options.headers['apns-push-type'],'alert');
  assert.equal(options.headers['apns-topic'],e.APNS_BUNDLE_ID);
  const jwt=options.headers.authorization.slice(7).split('.');
  assert.equal(jwt.length,3);
  assert.equal(JSON.parse(Buffer.from(jwt[0],'base64url').toString()).alg,'ES256');
  assert.equal(JSON.parse(Buffer.from(jwt[1],'base64url').toString()).iss,e.APNS_TEAM_ID);
  assert.equal(await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},e.verifyKey,
    Buffer.from(jwt[2],'base64url'),new TextEncoder().encode(jwt[0]+'.'+jwt[1])),true);
  assert.deepEqual(JSON.parse(options.body),{aps:{alert:{title:'Spyder Network',body:'Новое зашифрованное сообщение'},sound:'spyder_receive.caf','thread-id':'spyder.chat'},spyder_event:'message'});
  assert.equal(options.body.includes('secret'),false);
});

test('Provider credentials are required, malformed tokens are rejected, sandbox supported',async()=>{
  assert.equal(apnsConfigured({}),false);
  assert.equal(await sendAPNs({},token,'message',async()=>{throw Error('must not reach')}),0);
  const e=await env();e.APNS_ENVIRONMENT='development';let endpoint='';
  assert.equal(await sendAPNs(e,token,'invite',async url=>{endpoint=url;return {status:200}}),200);
  assert.match(endpoint,/api\.development\.push\.apple\.com/);
  assert.equal(await sendAPNs(e,'invalid','invite',async()=>{throw Error('must not reach')}),0);
});

test('Push routes require authorization and never reveal stored APNs token',async()=>{
  const db=new Map(),pending=[];
  const storage={get:async k=>db.get(k),put:async(k,v)=>{db.set(k,v)},delete:async k=>db.delete(k),
    list:async({prefix})=>new Map([...db].filter(([k])=>k.startsWith(prefix)))};
  const e=await env(); const hub=new ChatHub({storage,waitUntil:task=>pending.push(task)},e);
  const call=async(method,path,body,auth)=>{
    const headers={};if(auth)headers.authorization='Bearer '+auth;
    const response=await hub.fetch(new Request('https://test.example'+path,{method,headers,
      body:body?JSON.stringify(body):undefined}));return {status:response.status,body:await response.json()};
  };
  const id='a'.repeat(32),secret='b'.repeat(64);
  assert.equal((await call('POST','/v2/push/register',{token})).status,401);
  assert.equal((await call('POST','/v1/register',{id,secret,invite_code:'A'.repeat(24),name:'A'})).status,201);
  const auth=id+'.'+secret;
  assert.deepEqual((await call('GET','/v2/push/status',null,auth)).body,{provider_ready:true,enabled:false,sound:null,last_apns_status:null,last_attempt_at:null});
  assert.equal((await call('POST','/v2/push/register',{token:'wrong'},auth)).status,400);
  assert.equal((await call('POST','/v2/push/register',{token},auth)).status,200);
  const info=(await call('GET','/v2/push/status',null,auth)).body;
  assert.deepEqual(info,{provider_ready:true,enabled:true,sound:'system',last_apns_status:null,last_attempt_at:null});
  assert.equal(JSON.stringify(info).includes(token),false);
  assert.equal((await call('POST','/v2/push/unregister',{},auth)).status,200);
  assert.equal(db.has('push:'+id),false);
  await Promise.all(pending);
});


test('Sonic sound controls: original CAF, system default, mute, and invite cue', async()=>{
  const e=await env(); const payloads=[];
  const fetcher=async(url,options)=>{payloads.push(JSON.parse(options.body));return {status:200};};
  assert.equal(await sendAPNs(e,token,'message',fetcher,'pulse'),200);
  assert.equal(payloads[0].aps.sound,'spyder_receive.caf');
  assert.equal(await sendAPNs(e,token,'invite',fetcher,'pulse'),200);
  assert.equal(payloads[1].aps.sound,'spyder_connect.caf');
  assert.equal(await sendAPNs(e,token,'test',fetcher,'system'),200);
  assert.equal(payloads[2].aps.sound,'default');
  assert.equal(await sendAPNs(e,token,'message',fetcher,'mute'),200);
  assert.equal(Object.hasOwn(payloads[3].aps,'sound'),false);
  for(const payload of payloads) {
    assert.equal(JSON.stringify(payload).includes(token),false);
    assert.equal(JSON.stringify(payload).includes('private_key'),false);
  }
});

test('Changing sound and display name is authenticated, non-sensitive and persistent',async()=>{
  const db=new Map(),pending=[];
  const storage={get:async k=>db.get(k),put:async(k,v)=>db.set(k,v),delete:async k=>db.delete(k),
    list:async({prefix})=>new Map([...db].filter(([k])=>k.startsWith(prefix)))};
  const hub=new ChatHub({storage,waitUntil:task=>pending.push(task)},await env());
  const req=async(method,path,body,auth)=>{
    const headers={};if(auth)headers.authorization='Bearer '+auth;
    const r=await hub.fetch(new Request('https://test.example'+path,{method,headers,
      body:body===undefined?undefined:JSON.stringify(body)}));return {status:r.status,body:await r.json()};
  };
  const id='3'.repeat(32),secret='4'.repeat(64),auth=id+'.'+secret;
  assert.equal((await req('POST','/v2/profile/name',{name:'New'})).status,401);
  assert.equal((await req('POST','/v1/register',{id,secret,invite_code:'F'.repeat(24),name:'Old'})).status,201);
  assert.equal((await req('POST','/v2/profile/name',{name:'   '},auth)).status,400);
  assert.deepEqual((await req('POST','/v2/profile/name',{name:'New name'},auth)).body,{name:'New name'});
  assert.equal((await req('GET','/v1/me',undefined,auth)).body.name,'New name');
  assert.equal((await req('POST','/v2/push/preferences',{sound:'pulse'},auth)).status,409);
  assert.equal((await req('POST','/v2/push/register',{token,sound:'pulse'},auth)).status,200);
  assert.equal((await req('POST','/v2/push/preferences',{sound:'danger.caf'},auth)).status,400);
  assert.equal((await req('POST','/v2/push/preferences',{sound:'mute'},auth)).status,200);
  assert.equal((await req('GET','/v2/push/status',undefined,auth)).body.sound,'mute');
  assert.equal((await req('POST','/v2/push/test',{},auth)).status,200);
  assert.equal((await req('POST','/v2/push/test',{},auth)).status,200);
  assert.equal((await req('POST','/v2/push/test',{},auth)).status,200);
  assert.equal((await req('POST','/v2/push/test',{},auth)).status,429);
  await Promise.all(pending);
});
