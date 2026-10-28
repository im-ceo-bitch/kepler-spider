# Spyder Wallet v0.3 — cumulative TestFlight build

This source keeps the existing `com.console.beta` Apple identity and `Console` scheme.
It combines Premium UI v0.2 with BIP39 onboarding and Keychain gating v0.3.

**NOT READY FOR REAL FUNDS.** No on-chain addresses, transaction signing, backend chat, live RPC or asset balances.
Store only test mnemonics in this unaudited build. Wallet secret is device-bound, does not sync to iCloud, and is unrecoverable without the offline phrase after device loss.

## TestFlight signing (October 2026)

See **SIGNING_SETUP_RU.md**. The new workflow requires Apple Distribution P12 and
App Store Connect provisioning profile secrets for deterministic CI signing.
Run `build_only=true` to validate Debug/Release without distribution secrets.
Note: the legacy auto-unpack bot protects `.github/workflows` and does not update workflows.

## Build

The `console-update*.zip` patch contains the source changes and **does not replace any existing `.github/workflows`**. Upload one update ZIP to the repository root, wait for the auto-unpack workflow, and run the existing tested Intel TestFlight workflow.
`project.yml` includes the pinned Swift Package `BIP39MnemonicKit` version 2.0.1, resolved on GitHub Actions.

See `PATCH_README_RU.md` for details.
