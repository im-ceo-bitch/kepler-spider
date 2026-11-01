# SpyderTerminalKit v2 — RU / EN, iOS 17+

Independent local Swift Package for **Spyder Wallet / Spyder Network**. Includes bilingual command catalog, native SwiftUI chat/terminal switch, terminal settings, autocomplete, execution bridge, and enforced sensitive-action preview/confirmation.

## This release

| Component | Status |
|---|---|
| Russian prefix `сп`, English prefix `sp` | Implemented |
| Beginner phrase catalog and Standard exact syntax | Implemented (28 IDs; 87 RU + 83 EN patterns) |
| Autocomplete after 2–3 characters | Implemented |
| `SpyderChatTerminalSwitchView` with chat / terminal control | SwiftUI source included; Apple build not tested |
| Terminal preferences and in-memory command transcript | Implemented |
| Real action adapters via `TerminalActionRegistryHost` | Implemented; host app must register existing services |
| Sensitive wallet transfer / bulk send confirmation | Gate implemented; app services must provide backend-verified preview and reauthorize |
| Actual wallet/chat/profile service integration | **Not yet connected — current application repository unavailable** |
| Arbitrary natural-language NLU | Not implemented (catalog phrase matching only) |
| JavaScript execution | Not implemented (input is rejected safely) |
| Full iOS Xcode and TestFlight build | Not performed |

## Important

This ZIP is a **standalone Swift Package**, not a blind patch for your app unpacker. Do **not** upload it over `kepler-spider-main` as though it were an integrated update. First inspect the current repo, register real app service callbacks and add this package as a dependency. See [the Russian integration guide](Documentation/HOST-INTEGRATION-RU.md) and [architecture](Documentation/ARCHITECTURE.md).

The existing original v1 command resources, parser, input, settings, and tests remain included. New v2 modules: `TerminalActionBridge.swift`, `TerminalActionRegistryHost.swift`, `TerminalChatShell.swift` and additional tests.

## Tests

Run `swift test` on a development machine. Unit tests compile on Linux (non-SwiftUI sources). The iOS SwiftUI view code requires Xcode/macOS compilation and must be validated with real application sources before TestFlight.
