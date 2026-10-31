# Spyder MessageChain Research Wire Protocol 0.1

- Envelope V1: fixed-order Ed25519 signed message, sender chain sequence/hash, optional peer-head cross-reference, encrypted ciphertext. Independent sender chains allow concurrent messages.
- Signer public key is a temporary **per-conversation** demo key; binding to wallet-owned identity and hidden contacts is not implemented.
- A message is verified by both Ed25519 signature and AES-256-GCM authentication at the recipient. The relay sees conversation ID, sender key, sequence, timestamps and ciphertext length. Thus this demo does **not** provide metadata privacy.
- Relay keeps up to 1,000 encrypted records per conversation and refuses more; no silent pruning or unbounded storage.
- Integrity of a signature/hash does not guarantee that no data was omitted by a malicious server. Anti-rollback requires locally stored trusted heads and a consistency protocol.
- This is **not a consensus blockchain**: for a true distributed ledger we must define independent validators, fork handling, censorship resistance and availability. Do not publish as mainnet.
- Recipient X25519 static private-key compromise allows decryption of previously captured demo messages. Production will need an audited ratchet or MLS and independent messaging identities.
- Business goals: zero phone/email, no public directory by default, wallet-linked identity with independent chat keys; goals **not yet implemented**.
