# Spyder ID — UI preview, stage 1

Entry: Wallet → Spyder ID card → Open vault demo.
Screens: introduction, vault categories and sample search, credential detail,
document placeholder, note detail, add selector, read-only sample editors,
document submission/review preview, protection settings, Safari integration explanation.

This patch intentionally has no real secret entry, storage, authentication,
clipboard, file import/export, AI, AutoFill provider or Safari extension.
Navigation, sample search, category selection and showing a fictional password
work solely to evaluate the UI. Unsupported actions are disabled and labelled.
The existing chat identity remains unchanged. RU/EN copy is included.
Uses existing WalletTheme, WalletCard and SpyderActionButtonStyle; iOS 17 APIs.

Apply the ZIP at repository root. Existing XcodeGen project.yml recursively
includes Console, so no project configuration or workflow changes are required.
If opening a previously generated Xcode project, regenerate it with the existing
project.yml before building so the new Swift file is included.

Input archive was truncated (missing central directory). 420 complete files
were recovered and their CRC32 checks verified. The truncated nested
spider-update.zip was not used. This is a small patch, NOT a replacement repository.
Only WalletHomeView.swift is modified; the preview source and this note are new.

Validation: structural checks and Swift grammar parse (see delivery report).
Swift compiler / Xcode build: not run; no Swift or Apple SDK in this environment.
Simulator: not run. Physical iPhone / iPad / Mac Catalyst: not run.
Manually verify iPhone 13 mini / iPhone 11, large Dynamic Type, VoiceOver,
sheet dismissal, categories, search empty state, detail back navigation and iPad layout.
