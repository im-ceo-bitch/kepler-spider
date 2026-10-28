# Spider Chain ↔ Spyder Wallet — integration contract (PROPOSED, NOT LIVE)

Blockchain source inspected: `kepler-blockchain-main.zip`, Spider Protocol v0.1 Rust ledger.
The **blockchain repository remains unchanged**; this document is a protocol handoff for the other chat.

## Confirmed on-chain invariants (already in Rust)

- chain ID: `spider-devnet-1`
- native asset ID: `SPD`, 9 decimals, atomic `u64` quantities
- test asset ID: `tUSD`, 6 decimals — fictional, NOT Tether USD₮
- address: lower-case `spider1` Bech32m, 20-byte truncated `SHA256(Ed25519_public_key)`
- signed transfer envelope: `{payload, public_key, signature}`
- payload fields: `chain_id`, `sender`, `recipient`, `asset_id`, `amount`, `nonce`, `gas_limit`, `max_fee_per_gas`, `expiry_height`
- transaction preimage: literal `SPIDER/TX/TRANSFER/V1\0`, then four `u32 BE length || UTF8` strings, then five `u64 BE` integers in field order
- signature Ed25519 strict verification, nonce equality, expiration, fee=21,000×price atomic SPD
- transactions are only committed by `Ledger.apply_block` in a **local Rust demo**, NOT by public network consensus.

## Wallet-only experimental key derivation (requires chain team approval before public mainnet)

BIP-39 mnemonic -> PBKDF2-HMAC-SHA512 (2048 iterations, salt `mnemonic`) -> SLIP-0010 Ed25519 path `m/44'/9999'/0'/0'` (all hardened). Coin type 9999 is a temporary experimental convention, NOT an officially registered SLIP-44 coin type.

Public fixture (mnemonic `abandon` x11 + `about`, **public insecure test phrase**):

- Ed25519 public key `a20a6cddb7cf52fbe4403024e1ce8463ac0d70870bac6f492f5d16ba405fde12`
- Spider address `spider134e7kqt50ferckw9tywcvwdlyp54sp8hz44efd`

DO NOT fund this public fixture address or use it with real assets.

## Needed before enabling wallet's Send SPD action

The blockchain repository must expose a **persistent, independently testable devnet node** and authenticated HTTPS RPC. Suggested API (not implemented yet):

- `GET /v1/chain` => `{chain_id, height, genesis_hash, protocol_version}`
- `GET /v1/accounts/{spider_address}` => `{address, nonce, balances: {SPD: "<u64 atomic string>"}, height}`
- `POST /v1/transactions` accepts exact Rust `SignedTransfer` JSON, returns `{tx_id,status}`; server must verify signature, nonce and fee before accepting.
- `GET /v1/transactions/{tx_id}` returns `{status: "pending|included|rejected", height?, block_hash?}`

Public node URL must match `spider-devnet-1` and a pinned genesis hash. Transactions must not be represented as confirmed until an authoritative node reports inclusion. After consensus work, distinguish `included` versus `finalized` explicitly. Test faucet is a separate devnet-only endpoint; never bundle a privileged/faucet signing key in iOS.

Until these APIs exist, the wallet derives a **locally verifiable SPD address only**; there are no valid network balances, sends or receipts.
