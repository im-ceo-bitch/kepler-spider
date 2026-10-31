import test from 'node:test';
import assert from 'node:assert/strict';
import { makeDemoIdentity, makeConversationId, encryptDemo, decryptDemo } from '../protocol/experimental-node-crypto.mjs';
import { verifyEnvelopeSignature, envelopeHash, validateNext, ZERO_HASH } from '../protocol/messagechain.mjs';

const fixture = async () => {
  const a=makeDemoIdentity(),b=makeDemoIdentity(),cid=makeConversationId();
  const first=await encryptDemo({conversationId:cid,sender:a,recipientEncryptionKey:b.encryptionKey,plaintext:'Привет, приватный чат!'});
  return {a,b,cid,first};
};

test('ciphertext-only envelope roundtrip and server verifiable Ed25519 signature',async()=>{
  const {b,first}=await fixture();
  assert.equal(await verifyEnvelopeSignature(first.envelope),true);
  assert.equal(decryptDemo(first.envelope,b),'Привет, приватный чат!');
  assert.equal(JSON.stringify(first.envelope).includes('Привет'),false);
  assert.equal((await envelopeHash(first.envelope)).length,64);
});
test('tampering ciphertext or sequence invalidates the signature',async()=>{
  const {first}=await fixture();
  const text={...first.envelope,ciphertext:Buffer.from('tampered').toString('base64')};
  const index={...first.envelope,sequence:2};
  assert.equal(await verifyEnvelopeSignature(text),false);
  assert.equal(await verifyEnvelopeSignature(index),false);
});
test('a different device cannot decrypt without recipient X25519 private key',async()=>{
  const {first}=await fixture();
  assert.throws(()=>decryptDemo(first.envelope,makeDemoIdentity()));
});
test('two sender chains support alternating encrypted messages',async()=>{
  const {a,b,cid,first}=await fixture();
  validateNext(first.envelope,null);
  const reply=await encryptDemo({conversationId:cid,sender:b,recipientEncryptionKey:a.encryptionKey,plaintext:'Секретный ответ',peerHead:first.hash});
  validateNext(reply.envelope,null);
  assert.equal(decryptDemo(reply.envelope,a),'Секретный ответ');
  const second=await encryptDemo({conversationId:cid,sender:a,recipientEncryptionKey:b.encryptionKey,plaintext:'Третье',previous:first,peerHead:reply.hash});
  validateNext(second.envelope,{sequence:1,head:first.hash});
  assert.equal(decryptDemo(second.envelope,b),'Третье');
  assert.throws(()=>validateNext(second.envelope,{sequence:0,head:ZERO_HASH}),/chain_conflict/);
});
test('duplicate, deleted predecessor and invented head are detected by local chain checks',async()=>{
  const {first}=await fixture();
  assert.throws(()=>validateNext(first.envelope,{sequence:1,head:first.hash}),/chain_conflict/);
  const broken={...first.envelope,previous_hash:'a'.repeat(64)};
  assert.throws(()=>validateNext(broken,null),/chain_conflict/);
});
