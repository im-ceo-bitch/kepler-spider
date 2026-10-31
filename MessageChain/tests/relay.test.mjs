import test from 'node:test';
import assert from 'node:assert/strict';
import relay, { SpyderMessageRoom } from '../relay/src/index.mjs';
import { makeDemoIdentity, makeConversationId, encryptDemo } from '../protocol/experimental-node-crypto.mjs';

class FakeStorage {
  constructor(){this.map=new Map();}
  async get(k){return this.map.get(k);}
  async put(k,v){this.map.set(k,v);}
  async transaction(fn){return fn(this);}
}
const token='test-only-operator-secret';
const setup=()=>{
  const rooms=new Map();
  const env={DEVNET_OPERATOR_TOKEN:token,MESSAGE_ROOMS:{
    idFromName:n=>n,get:id=>{
      if (!rooms.has(id)) rooms.set(id,new SpyderMessageRoom({storage:new FakeStorage(),getWebSockets:()=>[]}));
      return rooms.get(id);
    }
  }};
  const call=async(path,{method='GET',body,auth=true}={})=>{
    const headers=auth?{'x-spyder-devnet-token':token}:{};
    if (body) headers['content-type']='application/json';
    const res=await relay.fetch(new Request('https://demo.invalid'+path,{method,headers,body:body?JSON.stringify(body):undefined}),env);
    return {status:res.status,body:await res.json()};
  };
  return {call};
};

test('operator auth required for ciphertext-only devnet',async()=>{
  const {call}=setup();
  assert.equal((await call('/health',{auth:false})).status,200);
  assert.equal((await call('/v1/conversations/'+'a'.repeat(64)+'/envelopes',{auth:false})).status,403);
});

test('accepts signed blocks, rejects injection, duplicates, broken chains',async()=>{
  const {call}=setup();
  const alice=makeDemoIdentity(),bob=makeDemoIdentity(),cid=makeConversationId();
  const path='/v1/conversations/'+cid;
  const init=await call(path+'/init',{method:'POST',body:{participants:[alice.signingKey,bob.signingKey]}});
  assert.equal(init.status,201);
  const first=await encryptDemo({conversationId:cid,sender:alice,recipientEncryptionKey:bob.encryptionKey,plaintext:'секретный текст'});
  assert.equal((await call(path+'/envelopes',{method:'POST',body:first.envelope})).status,201);
  assert.equal((await call(path+'/envelopes',{method:'POST',body:first.envelope})).body.status,'already_seen');
  const history=await call(path+'/envelopes?after=0');
  assert.equal(history.body.envelopes.length,1);
  assert.ok(!JSON.stringify(history.body).includes('секретный текст'));
  const injected={...first.envelope,ciphertext:Buffer.from('inject').toString('base64')};
  assert.equal((await call(path+'/envelopes',{method:'POST',body:injected})).status,403);
  const fork=await encryptDemo({conversationId:cid,sender:alice,recipientEncryptionKey:bob.encryptionKey,plaintext:'forked'});
  assert.equal((await call(path+'/envelopes',{method:'POST',body:fork.envelope})).status,409);
  const second=await encryptDemo({conversationId:cid,sender:alice,recipientEncryptionKey:bob.encryptionKey,plaintext:'valid second',previous:first});
  assert.equal((await call(path+'/envelopes',{method:'POST',body:second.envelope})).status,201);
  assert.equal((await call(path+'/envelopes?after=1')).body.envelopes.length,1);
});
