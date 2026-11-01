# Spyder Network Chat v2 — Cloudflare Worker / Durable Objects

The v2 relay stores **encrypted message envelopes only**. iOS owns the X25519 private keys, Ed25519 signing keys and ChaChaPoly message encryption keys. Chat identity is independent from wallet BIP-39 phrases; do NOT use wallet phrases for chat recovery. The `/health` endpoint returns `{"service":"spyder-chat-devnet","version":2,"e2ee":true}`; iOS rejects older chat endpoints and **does not fall back to plaintext**.

## Release / migration order

1. Deploy the Worker **before** distributing the new iOS build. Use the existing Cloudflare account, `spyder-chat-devnet` Worker name, `CHAT_HUB` Durable Object binding, and original SQLite DO migration. Switching Cloudflare accounts or Worker names **does not** migrate chats/accounts.
2. From `server/`, run `npm ci` if the lockfile exists, otherwise `npm install`, then `npm run check`. Deploy through the repository's **Console — Deploy Realtime Server** manual workflow (or `npx wrangler deploy` with authorized credentials). The ZIP unpack bot commit may **not** trigger downstream workflows, so explicitly start the deployment workflow.
3. Confirm `GET https://<YOUR-WORKER-DOMAIN>/health` responds with version **2**, `e2ee:true` before launching a TestFlight build. The TestFlight workflow must inject `SPYDER_CHAT_SERVER_URL` (plain HTTPS URL). If Chat v1 remains deployed, the updated client intentionally refuses to send.
4. Build with the existing TestFlight workflow; test chats on **two real/simulator devices**, including registration, invite acceptance, first contact key fingerprint confirmation, sending in both directions, background lock, offline recovery and blocked contacts.

## Protocol and limits

* Registration: `POST /v1/register` now accepts additional immutable `keys: {version:2,key_agreement:<base64>,signature:<base64>}`; existing accounts upgrade via authenticated `POST /v2/keys/activate`. Changing published keys returns HTTP 409 and needs an explicit account migration, not silent rotation.
* `GET /v2/keys?peer=<id>` is allowed for accepted contacts only; client stores a device-only key pin (TOFU) and fails closed upon key substitution. Compare displayed safety fingerprints **out of band** before trusting first contact.
* `POST /v2/messages` accepts only signed envelopes `{recipient_id,client_id,ephemeral_key,recipient_box,sender_box,signature}`. `GET /v2/messages?peer=...` returns encrypted envelopes. The server assigns sender/created_at/id, but does not see message plaintext. Old `GET/POST /v1/messages` return **410**, never plaintext fallback.
* `POST /v2/contacts/block` removes mutual contact access and prevents new invitations; `GET/POST /v2/profile/privacy` manages public search visibility (hidden by default). Invitations by private users work via invite code. There is basic DO-storage rate limiting.
* Keypair encryption: one-time ephemeral X25519 per message, HKDF-SHA256, ChaChaPoly recipient and sender copies; Ed25519 signature over every encrypted field plus sender/recipient/client IDs. Envelopes are bounded to 300 latest messages per conversation. Server sees **metadata**, timestamps, participant IDs, and ciphertext lengths.

## Explicit security gaps

* **Not yet an independently audited messenger.** There is no Double Ratchet, skipped-message-key management, multi-device sync, formal authentication handshake or key transparency. Compromise of a participant's **long-term device key can expose archived ciphertext**, so this implementation does **not** provide long-term forward secrecy. Fingerprint checks are mandatory to mitigate first-contact server key substitution.
* Keys are non-synchronizing device-only Keychain entries. If they are lost, a wallet seed or iCloud wallet backup **cannot** decrypt old chat messages. An explicit chat identity migration/rekey recovery protocol must be designed before public release.
* Existing plaintext v1 message records in prior DO storage are **not automatically deleted or converted**. Plan a retention/erasure migration with consent and backups before erasure. v2 clients neither display those historic messages nor add new plaintext messages.
* A single DO is a development topology. Before a large-scale rollout, add multi-room partitioning, abuse controls/WAF, monitoring, resilient backups, mobile push transport and independent cryptographic/security review.

## Tests

`cd server && npm run check` runs syntax verification and v2 relay tests (auth, consent, disabled plaintext, encrypted envelopes, idempotency, immutability, blocking, visibility). iOS tests in `Tests/SpyderE2EEV2Tests.swift` are designed for the **macOS Xcode test runner** and include a sender-copy round-trip, tampering and pin substitution; they are not executable on Linux.
