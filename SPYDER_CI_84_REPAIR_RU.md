# Spyder CI repair — 2026-11-01

This cumulative fix applies **after** the Terminal Kit v2 + CI Merge update.

- `Console/Features/Chats/ChatDetailView.swift`: reconnects the *actual* `SpyderChatTerminalView` behind the Chat/Terminal switch, maintaining E2EE chat and its original message handling. The terminal stays scoped to the active chat and uses the existing authenticated actions.
- `Console/ConsoleApp.swift`: injects `WalletAddressBookStore` into SwiftUI and switches its wallet-scoped public recipient entries when the active wallet changes. All existing market, push and secure lifecycle behavior is retained.

No server, CI test, seed phrase or cryptographic code is modified.

Tests before uploading: `python -m unittest discover -s ci/tests -p 'test_*.py'` with the latest checked-out repository, then full `xcodebuild` through build-only GitHub Actions. Do not re-run an old failed job: start a NEW run after the unzip commit.

**ZIP unpacking:** Both code files are nested under `Console/`, and the README remains at archive root to prevent the unzip workflow from treating `Console` as a disposable wrapper.
