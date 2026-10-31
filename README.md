> New Apple ID / TestFlight: see [SPYDER_NEW_APPLE_V060_README_RU.md](SPYDER_NEW_APPLE_V060_README_RU.md). This app is now `com.spyder.wallet`. Old Console signing guidance is obsolete.

# Spyder Wallet — v0.5 devnet

Cumulative SwiftUI iOS wallet update, Bundle ID `com.spyder.wallet`, Console scheme kept for TestFlight.

- Wallet/Core: Premium UI, native launch and onboarding, BIP-39 encrypted Keychain vault, Wallet Core read-only ETH/SOL/BTC address previews.
- Spider Chain: a test-only BIP-39/SLIP-0010-derived Bech32m `spider1…` address with an independent reference vector. No network transactions until actual Spider Chain RPC.
- Chats: Cloudflare Worker/SQLite Durable Object backend with separate device identity, invitation requests/acceptance and near-realtime polling. NO E2EE yet. No cryptocurrency key transmitted by chat.
- No fake coins, fake transactions, or default demo contacts in real Chats. Touch remains a labeled local UI prototype.

See `PATCH_README_RU.md`, `server/README.md`, `contracts/SPIDER_CHAIN_RPC_HANDOFF.md`.
