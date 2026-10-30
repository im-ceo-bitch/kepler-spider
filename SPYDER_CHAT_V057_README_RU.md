# Spyder Wallet — Chat integration patch v0.5.7 (current main)

Source: `kepler-spider-main 3.zip` provided in this conversation. The iumrah ZIP was inspected only as an interaction-design reference.

## Changed
- One chat engine: existing Console identity (`nodeID`), public `@handle`, handshakes, history and WebSocket. Removed the runtime choice between incompatible Console and devnet Chat UIs.
- Chats experience: search by `@username` (underlying Console handle), keyboard search, iumrah-style black/white bubbles with timestamps, copy actions, delivery labels, composer focus and light haptics.
- Chat enrollment prioritizes existing profile. Server setup is diagnostic fallback only; no new user-facing cloud configuration when the old endpoint is embedded/restored.
- Reinstated the original `CONSOLE_SERVER_URL` Info.plist substitution and Xcode build setting. The server URL must be supplied by CI and reach the original `console-realtime` Worker. An empty build setting does **not** create connectivity.

## Not changed
`ConsoleIdentity` Keychain service, `ConsoleSocket`, `ConsoleAPI` routes, wallet keys, Wallet UI, Bundle ID `com.console.beta`, Apple signing settings, original TestFlight pipeline, or Cloudflare server resources.

## REQUIRED: embed the working Console server URL
The existing ZIP auto-unpacker **ignores** `.github/workflows/*`. Thus the separate `spyder-chat-testflight.yml` must replace `.github/workflows/testflight.yml` manually.

This optional workflow variant retains the existing build/sign/upload commands, and adds:
1. `CONSOLE_SERVER_URL` GitHub Secret as preferred literal HTTPS URL; OR derives `https://console-realtime.<subdomain>.workers.dev` using existing `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` secrets.
2. GET `/health` verifying `service=console-realtime`, `status=READY`.
3. `CONSOLE_SERVER_URL` passed into `xcodebuild`, embedded in the archive's `Info.plist` and verified before upload.
4. Build-only can proceed without server URL, **but the resulting app will not have automatic chat connectivity**. For a functioning TestFlight chat both phones must connect to the same running original Console Worker.

Never substitute the separate `spyder-chat-devnet` Worker: its routes are incompatible with the original Console client.

## Security & current limitations
- Server-side identity is still the existing Console design; its `nodeID` is the stable internal user identifier; `@handle` is the public lookup alias.
- The supplied iumrah ZIP has only the client of a booking-specific care chat, not its server. Hence there is no way to copy its backend one-to-one from this archive.
- The original Console service reports `e2ee:false`; no end-to-end encryption here. Do not use for confidential messages, seeds, or secrets.
- No genuine two-iPhone delivery, live Worker availability or macOS Xcode compilation was verified in this environment.

## Gate
1. Upload `console-update-spyder-wallet-chat-unified-v057.zip` to root of current kepler-spider (only this update ZIP), wait for auto-unpack.
2. To embed the old endpoint, separately replace `.github/workflows/testflight.yml` with `spyder-chat-testflight.yml`. Do not place workflow inside update ZIP.
3. Run `Build only = true` to confirm Debug+Release compilation. Resolve all actual compiler errors before attempting TestFlight.
4. Configure/verify Cloudflare endpoint, then `Build only = false` only when the Apple signing setup is functional.
5. On two iPhones test username search, invitation/acceptance, A↔B delivery, reconnect, app relaunch history, UI with keyboard, no duplicate message.

## Local checks actually run
- `swiftc -frontend -parse` all current Swift sources: pass (syntax only, not iOS typechecking).
- `python ci/verify_repo.py`: pass.
- `node --check server/src/index.mjs`: pass; this is the new devnet server, **not** the legacy Console backend.
- `npm --prefix server test`: 1/1 pass, also checks devnet server only.
- YAML parse + `bash -n` on the optional workflow: pass.
- Manual contract assertions and ZIP overlay: pass.
- Full Xcode build and end-to-end Console production server test: NOT performed.
