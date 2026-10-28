# Spyder Wallet — Console migration / UI Foundation 0.1

Native iOS application prototype built with SwiftUI. Supersedes the former Console messenger UI while retaining the **existing App Store identity** for an in-place TestFlight update.

## Apple identity that must remain unchanged

- Bundle ID: `com.console.beta`
- XcodeGen project / target / scheme: `Console`
- Source target: `Console/`
- Existing GitHub Secrets names and signing machinery are retained in `.github/workflows/testflight-ios.yml`:
  `APPLE_TEAM_ID`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_BASE64`, `APPLE_DISTRIBUTION_P12_BASE64`, `APPLE_DISTRIBUTION_P12_PASSWORD`, `CONSOLE_IOS_PROFILE_BASE64`.
- Home screen display name: **Spyder Wallet**.
- Default marketing version: `1.3.0`, build number comes from the GitHub workflow run number. Check App Store Connect for version/build conflicts.

Certificates, API credentials and provisioning profiles do **not** live in this ZIP. They must already exist as valid GitHub Actions secrets / Apple portal records.

## UI foundation included

- Wallet & Chats: two custom capsule tabs, native SwiftUI.
- Wallet: monochrome balance card, Send / Receive / Touch, activity samples.
- Chats: searching, sample people and local-only draft conversation.
- Transfer flow: amount entry and honest **preview-only** review state, no cryptographic signing.
- Touch: animated pairing concept, simulator button only; no Nearby Interaction or NFC pairing.
- Profile: light / dark / follow system. Adaptive colors, SF Symbols, responsive layout.
- New app icon: monochrome Spyder symbol derived from the brand slide supplied by the user.

## NOT IMPLEMENTED (do not market as production wallet)

- No wallet key generation, secure keychain, seed recovery, real wallet addresses, blockchain RPC, signing, network balances, price feed or real money.
- No actual encrypted chat, push, real user login, touch pairing or nearby transfers.
- The demo balances, people and messages are UI samples, not persistent accounts.

**Do not submit the current demo as a functional cryptocurrency wallet for public review.** Test the UI first. Apple currently limits wallet apps to developers enrolled as organizations (App Review Guideline 3.1.5(i)); live crypto activity requires compliance checks.

## Build via GitHub Actions

1. Replace the old repository contents with this clean source **as a commit** (not a ZIP stored without unpacking). Existing repository and secrets must be retained. `project.yml` still produces the `Console` Xcode target.
2. Go to GitHub → Actions → **Spyder Wallet - TestFlight (Console ID)** → Run workflow. The job generates the `.xcodeproj` with XcodeGen, validates Apple secrets, builds simulator, archives and signs iOS, exports and uploads to App Store Connect/TestFlight.
3. Check processing status and install through TestFlight. Running the workflow is not the same as App Store approval.
4. In App Store Connect, change the *storefront name* and metadata separately when preparing the real version; `CFBundleDisplayName` changes the iPhone icon label but not the App Store product-page name automatically.

## Important: using the old `console-update*.zip` autobot

The original console auto-unpacker **explicitly refuses to edit `.github/workflows`**. A zip overlay alone cannot install the clean TestFlight workflow or remove its Cloudflare dependency. Therefore a separate migration ZIP is provided with the minimal compatible steps and a `.console-delete` manifest; this gives a usable **UI migration through your established console ZIP flow**, but leaves legacy Cloudflare workflows/server unused in the repository until the GitHub workflow files are updated manually. For an actually clean repository use this full source and updated workflows.

## Data migration

Because the bundle ID is unchanged, iOS keeps the app's old sandbox and possibly Keychain data when the app is updated. This version does **not** delete existing Console user data and does not contact its old backend. Before any public rollout, design an explicit consented clean-up/migration, account-deletion flow, updated privacy policy and release notes for existing Console users.

## Validation limits

All Swift files were checked using `swiftc -frontend -parse`. This environment is Linux, so it cannot run a real SwiftUI/Xcode build or verify certificate/profile secrets. GitHub Actions/macOS is the compilation and signing acceptance test.
