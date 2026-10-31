/**
 * Spyder MessageChain v0.1 — experimental signed encrypted conversation log.
 * The server receives ciphertext only. This is NOT a ratcheting E2EE protocol,
 * does NOT provide forward secrecy against compromise of the recipient's
 * long-term X25519 key, and is NOT a globally-consensed blockchain.
 * No wallet seed or wallet private key is used or accepted by this module.
 *
 * Wire format is intentionally deterministic. DO NOT casually change the order
 * of signedFields(); doing so would invalidate previous signatures.
 */
export const PROTOCOL_VERSION = 1;
export const ZERO_HASH = '0'.repeat(64);
export const MAX_CIPHERTEXT_BYTES = 16_384;

const b64Pattern = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
const isB64 = (value, min, max) => {
  if (typeof value !== 'string' || !b64Pattern.test(value)) return false;
  const len = Math.floor(value.length * 3 / 4) - (value.endsWith('==') ? 2 : value.endsWith('=') ? 1 : 0);
  return len >= min && len <= max;
};
export const isHexHash = value => typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);

export function validateEnvelopeShape(e) {
  if (!e || typeof e !== 'object' || Array.isArray(e)) throw new Error('invalid_envelope');
  const allowed = ['version','conversation_id','sender_key','sequence','previous_hash','peer_head','ephemeral_key','nonce','ciphertext','auth_tag','sent_at','signature'];
  if (Object.keys(e).length !== allowed.length || Object.keys(e).some(k => !allowed.includes(k))) throw new Error('invalid_fields');
  if (e.version !== PROTOCOL_VERSION) throw new Error('unsupported_version');
  if (!isHexHash(e.conversation_id)) throw new Error('invalid_conversation_id');
  if (!isB64(e.sender_key, 40, 100)) throw new Error('invalid_sender_key');
  if (!Number.isSafeInteger(e.sequence) || e.sequence < 1 || e.sequence > 10_000_000) throw new Error('invalid_sequence');
  if (!isHexHash(e.previous_hash) || !isHexHash(e.peer_head)) throw new Error('invalid_link');
  if (!isB64(e.ephemeral_key, 40, 100)) throw new Error('invalid_ephemeral_key');
  if (!isB64(e.nonce, 12, 12)) throw new Error('invalid_nonce');
  if (!isB64(e.ciphertext, 1, MAX_CIPHERTEXT_BYTES)) throw new Error('invalid_ciphertext');
  if (!isB64(e.auth_tag, 16, 16)) throw new Error('invalid_auth_tag');
  if (!Number.isSafeInteger(e.sent_at) || e.sent_at < 1_600_000_000_000) throw new Error('invalid_timestamp');
  if (!isB64(e.signature, 64, 64)) throw new Error('invalid_signature');
  return e;
}

export function signedFields(e) {
  return [
    'SPYDER-MESSAGECHAIN-ENVELOPE-V1', e.version, e.conversation_id,
    e.sender_key, e.sequence, e.previous_hash, e.peer_head,
    e.ephemeral_key, e.nonce, e.ciphertext, e.auth_tag, e.sent_at
  ];
}
export const signingBytes = e => new TextEncoder().encode(JSON.stringify(signedFields(e)));

export async function envelopeHash(e) {
  validateEnvelopeShape(e);
  const data = new TextEncoder().encode(JSON.stringify([...signedFields(e), e.signature]));
  const digest = await globalThis.crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(digest)].map(x => x.toString(16).padStart(2,'0')).join('');
}

export async function verifyEnvelopeSignature(e) {
  validateEnvelopeShape(e);
  try {
    const keyBytes = Uint8Array.from(atob(e.sender_key), c => c.charCodeAt(0));
    const sigBytes = Uint8Array.from(atob(e.signature), c => c.charCodeAt(0));
    const key = await globalThis.crypto.subtle.importKey('spki', keyBytes, { name: 'Ed25519' }, false, ['verify']);
    return globalThis.crypto.subtle.verify('Ed25519', key, sigBytes, signingBytes(e));
  } catch {
    return false;
  }
}

export function validateNext(e, state) {
  // The relay chains messages separately for each signer (duplex log).
  const prev = state || { sequence: 0, head: ZERO_HASH };
  if (e.sequence !== prev.sequence + 1 || e.previous_hash !== prev.head) {
    throw new Error('chain_conflict');
  }
}
