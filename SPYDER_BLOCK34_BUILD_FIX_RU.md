# Spyder Wallet — Block 3–4 + Build CI hotfix (2026-11-01)

## Diagnosis from GitHub Actions `logs_111904303393 2.zip`

Build stopped in `Verify source and run unit tests` **before** xcodebuild.
Old regression `ci/tests/test_spyder_live_release.py` expected
`WalletSendAvailabilityView()` while Block 1–2 replaced that with
`WalletSendFlowView(preselected: sendChain)`.

The checked-out revision at failing run (`2e1ddcb4177031be8f115b9c8745a480d212e10c`)
also still had the original devnet test. This means the CI checkout was not
fully updated to Block 3–4 at the moment this run started.

## Contents

This is a **cumulative Block 3–4 overlay** on top of Block 1–2, not a
replacement for Block 1–2 and not a separate patch that requires an older
Block 3–4 ZIP. It includes the Block 3–4 changes and a CI regression test
that checks:
- Mainnet send opens the new review-only flow;
- broadcast remains explicitly disabled;
- Spider Devnet on the home screen is either not visible or gated behind
  an explicit configured endpoint;
- existing chat setup, address caching, market and auth gates remain intact.

No `.github/workflows` files are included or altered.

## Installation

1. Make sure Block 1–2 is already installed in your repo's main branch.
2. Upload ONLY `console-update-spyder-wallet-block34-buildfix-20261101.zip`
   to the repository root. Do not leave other `console-update*.zip` there.
3. Wait for `Console — Auto Unpack Update` to finish green and verify that
   its commit landed in main, before manually running TestFlight.
4. Then run the TestFlight build-only/archival workflow.
5. Deploy Chat v2 server before running the newly patched client, according
   to `SPYDER_WALLET_BLOCK34_RU.md`.

## Tests run locally

- `python3 ci/verify_repo.py`: PASS.
- `python3 -m unittest discover -s ci/tests -v`: 18/18 PASS on Block 1–2
  and Block 1–4 overlays.
- `python3 -m unittest discover -s tests -q`: 10/10 PASS on Block 1–2,
  16/16 PASS on Block 1–4.
- `node --test MessageChain/tests/*.test.mjs`: 7/7 PASS on both overlays.
- `node --test server/test/chat.test.mjs`: PASS on Block 1–4.
- `swiftc -frontend -parse` on Console Swift source tree: PASS.

Full Apple SDK typecheck, Xcode archive and TestFlight were NOT executed in
this Linux environment. This package remedies the failure shown in the supplied
log; a subsequent Xcode build could surface additional errors.
