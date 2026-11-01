# Spyder Terminal Kit · RU / EN

**Standalone Swift Package starter kit** for Spyder Network / Spyder Wallet (iOS 17+).
This is a reusable language/catalog/parser/UI foundation; it does **not** modify any existing app repository and does **not** perform wallet transfers, change app data, or execute arbitrary JavaScript.

## Included

- `commands.ru.json` / `commands.en.json` — 28 matching action IDs, 91 RU + 86 EN phrase patterns in both Beginner and Standard levels.
- `TerminalEngine` — matching and parameter extraction (preserves user message case), bilingual prefix detection (`сп` / `sp`), stable typed action IDs and safe intent validation.
- `TerminalEngine.suggestions` — autocomplete after 2 or 3 typed characters, ordered suggestions, configurable limit.
- `SpyderTerminalInputView` — native SwiftUI text input with interactive command suggestions, sends parsed results to an app callback.
- `SpyderTerminalSettingsView` — native SwiftUI settings (level, language, appearance, accent, autocomplete, font size, haptics, history toggle).
- `TerminalSettingsStore` — optional local settings persistence in UserDefaults, **preferences only**.
- 16 Swift Package tests on Linux.

## Quick start

1. In Xcode use **File → Add Package Dependencies → Add Local…**, select this package folder.
2. Import `SpyderTerminalKit` in the host app.
3. Bind a `TerminalSettings` state and display `SpyderTerminalInputView` inside the existing Chat / Terminal switcher.
4. Handle `.matched(TerminalMatch)` using existing Chat / Wallet / Profile / Settings services. **Never directly execute unreviewed natural-language output.**
5. Persist settings when they change.

```swift
import SwiftUI
import SpyderTerminalKit

struct ChatTerminalExample: View {
    @State private var settings = TerminalSettingsStore().load()
    @State private var lastActionID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spyder Terminal")
            SpyderTerminalInputView(settings: $settings) { result in
                switch result {
                case .matched(let action):
                    // Replace this with the app's permission-checked command router.
                    // action.needsConfirmation == true means REVIEW and CONFIRM first.
                    lastActionID = "Recognized: \(action.commandID)"
                case .suggestions: lastActionID = "Choose a suggestion"
                case .developerInput: lastActionID = "Professional executor unavailable"
                case .unrecognized: lastActionID = "Unknown command"
                }
            }
            Text(lastActionID).font(.caption)
        }
        .onChange(of: settings) { _, value in
            try? TerminalSettingsStore().save(value)
        }
    }
}
```

### Russian and English examples

```text
сп измени фон                      -> chat.background.change  (open picker)
sp change background               -> chat.background.change  (open picker)
сп измени тему чата на киберпанк   -> chat.theme.set {theme: cyberpunk}
sp change chat theme to Chrome     -> chat.theme.set {theme: chrome}
сп покажи баланс                   -> wallet.balance
sp show balance                    -> wallet.balance
```

Supported theme **identifiers**: `chrome`, `cyberpunk`, `thunder` (aliases `хром`, `киберпанк`, `гром`). The actual chat theme assets and UI theming must exist in your app; this library only resolves theme IDs.

## Boundaries / status

| Feature | Status |
|---|---|
| RU/EN structured command dictionaries | Included |
| Beginner: curated natural variants | Included |
| Beginner: unrestricted conversational NLU | Provider integration **required** |
| Standard: RU `сп`, EN `sp` commands | Included |
| Autocomplete after 2–3 characters | Included |
| Native SwiftUI input / settings | Source included, **not iOS/Xcode compiled** here |
| Runtime connection to actual apps | **Not included** (repository not provided) |
| Chat themes (Chrome / Cyberpunk / Thunder) rendering | **Not included** |
| Full JavaScript engine / runtime | **Not included** |
| Production wallet signing / confirmation | **Not included** |

### Beginner freeform NLU contract

Freeform requests such as `Сделай мне красивый фон переписки в стиле Cyberpunk` need an optional on-device or backend natural-language interpreter. That interpreter must return ONLY a structured action ID + parameters, e.g.:

```json
{"actionID":"chat.theme.set", "parameters":{"theme":"cyberpunk"}}
```

Then call `engine.validatedIntent(actionID:parameters:language:)`. Unknown actions and unexpected properties must be rejected. The host app must enforce permissions, resource ownership, explicit review for sensitive actions, and anti-spam limits. No language model may directly call a wallet signer or message sender.

### Recommended terminal settings

- Level: Beginner / Standard / Developer
- Command language: Auto / Русский / English
- Autocomplete: enabled, after 2–3 characters, max suggestions
- Terminal appearance: System / Dark / OLED
- Accent: Signal Red / Electric Blue
- Font size, haptics, command history toggle
- Never disable permission gates for sensitive operations

### Developer level

The Developer mode is a separate script input contract, **not** a shell/OS terminal. Suggested future API:

```javascript
await spyder.chat.setTheme("cyberpunk");
const wallet = await spyder.wallet.balance();
spyder.console.log(wallet);
```

Implement against a sandboxed allowlisted script API. A JavaScriptCore integration requires execution limits, permission checks, a robust asynchronous bridge, and review for compliance with App Store policies. Other languages require separately shipped and reviewed interpreters. Do not expose private keys, filesystem, OS commands or unrestricted networking.

## Validation

Run `swift test` from the project root. Tests validate RU/EN parity, theme aliasing, 2-character autocomplete, Standard/Beginner separation, text-case preservation, safe sensitive intent handling, and settings persistence.

Important: CI compilation and unit tests here ran on Linux. Apple-platform SwiftUI compilation and a real Xcode app build **have not been performed**.
