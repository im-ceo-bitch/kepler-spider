# Spyder Chat Devnet v0.5

An independent Cloudflare Workers + SQLite-backed Durable Object **test messenger**.
This is *not* a money-transfer system, has NO end-to-end encryption, and is NOT audited.
All chat content can be read by the operator of the Worker. Do NOT share mnemonic phrases or secrets.

## Deploy from the existing Console repository

This folder **replaces** the former `server/` folder from Console. The old `Console — Deploy Realtime Server` GitHub Actions workflow, if it remains in your GitHub repository, is already configured with `working-directory: server` and `npm install`, `npm run check`, `npx wrangler deploy`.

1. Upload the cumulative `console-update-spyder-wallet-livechat-v05.zip` into the **root of the wallet GitHub repository** and let the `Console — Auto Unpack Update` bot finish.
2. In **Actions**, manually run `Console — Deploy Realtime Server` (GitHub Actions `GITHUB_TOKEN` push from the unpacker does not trigger other workflows).
3. The deploy job requires `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` existing in repository Secrets with permission to deploy Workers / Durable Objects.
4. Copy the `https://spyder-chat-devnet.<account-subdomain>.workers.dev` URL from the deploy log and paste it into the **Chats** tab on both iPhones.
5. Both iPhones register different chat profiles. A copies their invitation code -> B invites A -> A accepts in Chats. Then send messages between devices.

If the old Console deploy workflow was deleted, create `.github/workflows/spyder-chat-deploy.yml` from the file `SPYDER_CHAT_DEPLOY.yml.txt` in the repo root. It cannot be installed by the old ZIP unpacker because that bot intentionally protects `.github/workflows/`.

## API (all data JSON; protected calls use Authorization: Bearer <id>.<64-hex-token>)

- `GET /health`
- `POST /v1/register` `{id, secret, invite_code, name}`
- `GET /v1/me`
- `GET /v1/contacts`
- `POST /v1/invites` `{code}`
- `POST /v1/invites/accept` `{from_id}`
- `GET /v1/messages?peer=<32hex>`
- `POST /v1/messages` `{recipient_id, client_id, text}`

Calls are authenticated with a randomly generated chat secret, **never a wallet private key**. Identities are device-local in iOS Keychain; currently there is no multi-device chat account recovery. The list of contacts is established only after an explicit invite acceptance. Messages are polled every ~3 seconds while a conversation is open; no background APNs, WebSocket, media, calls, or E2EE in v0.5.

This prototype keeps only the last 300 messages per pair in a single Durable Object; it is not production storage architecture.

## Test before deployment

`npm install && npm run check`

`npm run check` checks JavaScript syntax and tests authorization, explicit consent, actual storage/retrieval, idempotent message handling and unauthorized access.
