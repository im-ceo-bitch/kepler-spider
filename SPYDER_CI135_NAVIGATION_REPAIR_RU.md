# Spyder CI135 — Navigation + Terminal compatibility repair

Based on the failure in GitHub commit `61df08f5c10ebff415dfcf1264ff1bf7bc9ed970`.

- Replaces old WalletRootView single-path modal navigation with independent Wallet and Network stacks.
- Keeps the real global Terminal tab, its authenticated host and 35-command v5 catalog.
- Keeps Chat/Terminal wrapper for a conversation, public profile navigation, real Wallet financial routes, and APNs deep-link handling.
- Updates three outdated CI assertions without removing security checks: the old 28-command count, the former WalletSettings location of terminal preferences, and the old fullScreenCover Wallet Control Center.
- No changes to cryptographic keys, server, Cloudflare, Apple signing, Personas, message protocol, or wallet balances.

This ZIP is an overlay and contains four code/test paths plus this document. Extract in the root of `im-ceo-bitch/kepler-spider` via the existing console-update unpacker. Verify unpack step first, then run a **new build-only** CI from the updated commit, then TestFlight.

Verification performed locally:
1. Syntax-parse and structural route checks.
2. Apply the packaged ZIP to a fresh reconstructed pre-fix repository and rerun available 102 Python CI tests and structural checks.

Not verified: full 135-test suite against a full live GitHub checkout and a real `xcodebuild archive`. Do not treat static test success as a confirmed TestFlight build.
