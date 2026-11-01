# Spyder Unified Worker — MessageChain v1 + Chat v2

**Existing Cloudflare Worker:** `kepler-spider` at `https://kepler-spider.helloiumrah.workers.dev`.

This worker runs two **independent** protocols and two SQLite-backed Durable Object classes:

| Path / namespace | Service | Access |
|---|---|---|
| `GET /health` | MessageChain research devnet v1 health (unchanged) | Public |
| `/v1/conversations/{64hex}/{init,envelopes,socket}` | MessageChain / `MESSAGE_ROOMS` → `SpyderMessageRoom` | `x-spyder-devnet-token` required |
| `GET /chat/health` | Chat v2 health | Public |
| `/v1/register`, `/v1/me`, `/v1/invites`, `/v1/users/search`, `/v2/*` | Chat v2 / `CHAT_HUB` → `ChatHub` | Authenticated where required |

Chat v2 uses device-side X25519/Ed25519/ChaChaPoly. Only ciphertext envelopes are relayed. APNs notifications contain neutral text and no message content. This is pilot-grade security, not an independently audited messenger. MessageChain is an independent experimental protocol and retains its separate operator token.

The existing Durable Object class `SpyderMessageRoom` and migration tag `v1` are kept. A new migration `v2-add-chat-hub` introduces `ChatHub` without deleting or renaming the former. **Do not change Worker name, account, or remove legacy DO binding/migrations.** Check that the live migration history matches before deployment.

## Tests

From `server/`: `npm run check` (Node 22+ for tests); from repository root: `node --test MessageChain/tests/*.test.mjs`.

## Deployment

See `../SPYDER_UNIFIED_CHAT_DEPLOY_RU.md`. Before deploying, verify GitHub Secrets `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`, `SPYDER_CHAT_SERVER_URL` and deployed Worker APNs settings (`APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`, `APNS_ENVIRONMENT`). Do not paste credentials into git or iOS. Deploy using the existing `Console — Deploy Realtime Server` workflow only after confirming the correct account and `MESSAGE_ROOMS` binding.

Mobile uses `GET /chat/health` before registration. The old `/health` intentionally does **not** identify Chat v2.
