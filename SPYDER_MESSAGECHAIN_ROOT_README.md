# Spyder MessageChain — GitHub Auto-Unpack path fix v0.5.9.1

Этот файл намеренно лежит в корне ZIP. Он не даёт действию
`Console — Auto Unpack Update` ошибочно считать папку `MessageChain`
упаковочной обёрткой и удалить её.

После распаковки проверьте наличие:
- `MessageChain/relay/wrangler.jsonc`
- `MessageChain/relay/src/index.mjs`
- `MessageChain/protocol/messagechain.mjs`

Cloudflare Workers Builds:
- Project name: spyder-messagechain-devnet
- Path / Root directory: MessageChain/relay
- Build command: npm install && npm run check
- Deploy command: npx wrangler deploy

После развёртывания: добавьте в Worker runtime secret `DEVNET_OPERATOR_TOKEN`.
Это серверный операторский ключ для закрытого DEVNET, НЕ помещайте его в iOS.
Текущая версия не является готовым E2E-мессенджером.
