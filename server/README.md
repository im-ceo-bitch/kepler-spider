# Spyder Chat — Cloudflare Worker / Durable Objects

This is a device-identity 1:1 chat backend, separate from wallet private keys. The server persists messages **without end-to-end encryption**. It is not audited, and must not be used for mnemonics, passwords or private keys.

## Deployment for the Spyder Wallet TestFlight release

The provided `spyder-wallet-testflight-cloud-live.yml` workflow performs deployment on each release before building iOS. Required repository secrets:

- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_API_TOKEN` (Workers Scripts Write and permission to deploy Durable Objects)
- Existing App Store Connect API key secrets and `APPLE_TEAM_ID`

Flow: `npm install` -> `npm run check` -> `npx wrangler deploy` -> `GET Cloudflare Workers subdomain` -> probe `/health` -> embed exact HTTPS URL in app Info.plist -> Xcode archive -> cloud-sign -> TestFlight upload.

The iOS Chats tab does not prompt normal users to enter a server URL. Advanced diagnostic override is in Profile > Developer options. If Cloudflare deployment or `/health` fails, the release workflow **fails before compiling**.

The Worker uses the existing `spyder-chat-devnet` name and a SQLite-backed `ChatHub` Durable Object. Keep the same Cloudflare account and Worker name across releases to preserve chat history. Changing accounts or worker names does not migrate data.

## HTTP API

- `GET /health` (anonymous)
- `POST /v1/register` with random id/secret + public username/name (anonymous)
- `GET /v1/me` (bearer authenticated)
- `POST /v1/profile/username`
- `GET /v1/users/search?q=`
- `GET /v1/contacts`
- `POST /v1/invites` and `POST /v1/invites/accept`
- `GET /v1/messages?peer=` and `POST /v1/messages`

Invitations require acceptance before either user can read or send messages. Username is unique case-insensitively and is not an authentication secret. Credentials belong in the device's Keychain. No multi-device migration, notification service, E2EE, or message retention SLA are provided.

## Local validation

Run `npm install && npm run check` inside `server/`.
