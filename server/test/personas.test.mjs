import test from 'node:test';
import assert from 'node:assert/strict';
import {ChatHub} from '../src/index.mjs';
import {webcrypto} from 'node:crypto';
if (!globalThis.crypto) globalThis.crypto = webcrypto;

const ID = {public:'a'.repeat(32), private:'b'.repeat(32), friend:'c'.repeat(32)};
const KEY = id => ({version:2,key_agreement:Buffer.alloc(32,id).toString('base64'),signature:Buffer.alloc(32,id).toString('base64')});
function create() {
 const db=new Map();
 const storage={get:async k=>db.get(k),put:async(k,v)=>db.set(k,v),delete:async k=>db.delete(k),
   list:async ({prefix})=>new Map([...db].filter(([k])=>k.startsWith(prefix)))};
 const hub = new ChatHub({storage});
 const call=async(method,path,body,credential)=>{
   const headers={}; if(credential)headers.authorization='Bearer '+credential;
   if(body)headers['content-type']='application/json';
   const res=await hub.fetch(new Request('https://spyder.test'+path,{method,headers,body:body?JSON.stringify(body):undefined}));
   return {code:res.status,body:await res.json()};
 };
 const auth=id=>id+'.'+id[0].repeat(64);
 return {call,auth,db};
}
const avatar={version:1,style:'web',accent:'blue',seed:'f'.repeat(32)};
async function register(call,id,code,username) {
 return await call('POST','/v1/register',{id,secret:id[0].repeat(64),invite_code:code,name:id===ID.private?'Private':'Public',
    ...(username?{username}:{}), keys:KEY(id[0]),discoverable:Boolean(username)});
}
test('private Persona has no public handle, is not searchable and is only inviteable by secret code', async()=>{
 const {call,auth}=create();
 assert.equal((await register(call,ID.public,'A'.repeat(24),'publicuser')).code,201);
 assert.equal((await register(call,ID.private,'B'.repeat(24))).code,201);
 assert.equal((await register(call,ID.friend,'C'.repeat(24),'frienduser')).code,201);
 assert.equal((await call('GET','/v1/users/search?q=priv',null,auth(ID.friend))).body.users.length,0);
 assert.equal((await call('GET','/v2/profile/privacy',null,auth(ID.private))).body.discoverable,false);
 assert.equal((await call('POST','/v1/invites',{code:'B'.repeat(24)},auth(ID.friend))).code,200);
 assert.equal((await call('POST','/v1/invites/accept',{from_id:ID.friend},auth(ID.private))).code,200);
 assert.equal((await call('GET','/v1/contacts',null,auth(ID.private))).body.contacts[0].id,ID.friend);
});
test('avatar/bio/status are validated, retained and visible only to contacts for private account',async()=>{
 const {call,auth}=create();
 await register(call,ID.private,'B'.repeat(24)); await register(call,ID.friend,'C'.repeat(24),'frienduser');
 assert.equal((await call('GET','/v3/profile/contact?peer='+ID.private,null,auth(ID.friend))).code,403);
 assert.equal((await call('POST','/v3/profile',{bio:'Hello',status:'Testing',avatar:{...avatar,style:'invalid'}},auth(ID.private))).code,400);
 const updated=await call('POST','/v3/profile',{bio:'Hello',status:'Testing',avatar},auth(ID.private));
 assert.equal(updated.code,200);assert.deepEqual(updated.body.avatar,avatar);
 assert.equal((await call('GET','/v3/profile/me',null,auth(ID.private))).body.bio,'Hello');
 await call('POST','/v1/invites',{code:'B'.repeat(24)},auth(ID.friend));
 await call('POST','/v1/invites/accept',{from_id:ID.friend},auth(ID.private));
 const profile=await call('GET','/v3/profile/contact?peer='+ID.private,null,auth(ID.friend));
 assert.equal(profile.code,200);assert.deepEqual(profile.body.avatar,avatar);
 assert.equal((await call('GET','/v1/contacts',null,auth(ID.friend))).body.contacts[0].status,'Testing');
 assert.equal((await call('GET','/v3/profile/me',null,auth(ID.public))).code,401);
});
