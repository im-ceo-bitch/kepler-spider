/**
 * Test-only crypto adapter. Uses built-in Node.js crypto to illustrate the wire
 * protocol. It does not implement a Double Ratchet/MLS or a seed-derived ID.
 * DO NOT SHIP IN SPYDER WALLET AS A PRODUCTION CRYPTO IMPLEMENTATION.
 */
import { createHash, generateKeyPairSync, randomBytes, diffieHellman, hkdfSync, createCipheriv, createDecipheriv, sign, verify, createPublicKey } from 'node:crypto';
import { signingBytes, envelopeHash, ZERO_HASH, validateEnvelopeShape } from './messagechain.mjs';

const derBase64 = key => key.export({ format: 'der', type: 'spki' }).toString('base64');
export function makeDemoIdentity() {
  const signing = generateKeyPairSync('ed25519');
  const encryption = generateKeyPairSync('x25519');
  return { signing, encryption, signingKey: derBase64(signing.publicKey), encryptionKey: derBase64(encryption.publicKey) };
}
export const makeConversationId = () => randomBytes(32).toString('hex');
const messageKey = (shared, conversationId) => Buffer.from(hkdfSync('sha256', shared,
  createHash('sha256').update(`SPYDER-MESSAGECHAIN-V1:${conversationId}`).digest(),
  Buffer.from('demo-message-encryption-v1'), 32));
const aad = e => Buffer.from(JSON.stringify(['SPYDER-MESSAGECHAIN-AAD-V1',e.conversation_id,e.sender_key,e.sequence,e.previous_hash,e.peer_head,e.ephemeral_key,e.nonce,e.sent_at]));

export async function encryptDemo({ conversationId, sender, recipientEncryptionKey, plaintext, previous = null, peerHead = ZERO_HASH }) {
  if (!/^[0-9a-f]{64}$/.test(conversationId) || !/^[0-9a-f]{64}$/.test(peerHead)) throw new Error('invalid_conversation');
  if (typeof plaintext !== 'string' || Buffer.byteLength(plaintext, 'utf8') > 12_000 || !plaintext) throw new Error('invalid_plaintext');
  const ephemeral = generateKeyPairSync('x25519');
  const receiver = createPublicKey({ key: Buffer.from(recipientEncryptionKey, 'base64'), type: 'spki', format: 'der' });
  const shared = diffieHellman({ privateKey: ephemeral.privateKey, publicKey: receiver });
  const nonce = randomBytes(12);
  const header = {
    version: 1, conversation_id: conversationId, sender_key: sender.signingKey,
    sequence: (previous?.sequence || 0) + 1,
    previous_hash: previous?.hash || ZERO_HASH, peer_head: peerHead,
    ephemeral_key: derBase64(ephemeral.publicKey), nonce: nonce.toString('base64'),
    sent_at: Date.now()
  };
  const cipher = createCipheriv('aes-256-gcm', messageKey(shared, conversationId), nonce);
  cipher.setAAD(aad(header));
  const encrypted = Buffer.concat([cipher.update(plaintext,'utf8'), cipher.final()]);
  const envelope = {
    ...header, ciphertext: encrypted.toString('base64'), auth_tag: cipher.getAuthTag().toString('base64'), signature: ''
  };
  envelope.signature = sign(null, Buffer.from(signingBytes(envelope)), sender.signing.privateKey).toString('base64');
  validateEnvelopeShape(envelope);
  return { envelope, hash: await envelopeHash(envelope), sequence: envelope.sequence };
}

export function decryptDemo(e, recipient) {
  validateEnvelopeShape(e);
  const signer = createPublicKey({key:Buffer.from(e.sender_key,'base64'), type:'spki', format:'der'});
  if (!verify(null, Buffer.from(signingBytes(e)), signer, Buffer.from(e.signature,'base64'))) throw new Error('invalid_signature');
  const ephemeral = createPublicKey({key:Buffer.from(e.ephemeral_key,'base64'), type:'spki', format:'der'});
  const shared = diffieHellman({privateKey:recipient.encryption.privateKey, publicKey:ephemeral});
  const decipher = createDecipheriv('aes-256-gcm', messageKey(shared,e.conversation_id),Buffer.from(e.nonce,'base64'));
  decipher.setAAD(aad(e));
  decipher.setAuthTag(Buffer.from(e.auth_tag,'base64'));
  return Buffer.concat([decipher.update(Buffer.from(e.ciphertext,'base64')),decipher.final()]).toString('utf8');
}
