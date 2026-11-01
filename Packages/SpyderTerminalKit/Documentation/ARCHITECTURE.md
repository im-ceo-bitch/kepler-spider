# Architecture / Архитектура

```text
Existing Chat header   [Чат | Терминал]
                         |
             SpyderTerminalInputView
                         |
                    TerminalEngine
                   /       |       \
          commands.ru   commands.en  optional NLU
                  \       |       /
                   validatedIntent
                         |
                  Host Action Router  (to implement in application)
                         |
                Permissions & consent  (host application)
                         |
       Chat / Profile / Wallet / Network / Settings services
```

## Stable IDs

Both languages share the same action IDs. Phrase matching is locale-specific, but permissions and routing are independent of language. Never branch business logic on the UI text.

## Beginner / Новичок

A curated local phrase dictionary works without connectivity. Freeform commands need NLU, either on-device or a privacy-reviewed server. NLU produces candidates, not side effects; host presents a preview when interpretation is uncertain.

## Standard / Средний

Precise deterministic commands: `сп измени фон`, `sp change background`. Auto-detect typed prefix, even if UI locale is fixed differently. Suggestions start at 2 characters by default.

## Developer / Профессиональный

Offer a script editor (JavaScript first). Expose limited, versioned `spyder.*` APIs only. Do not present this as a real Unix shell. Run controlled and limited scripts; wallet signing and bulk sends always leave the script and require a privileged confirmation user interface.

## UI contract

The terminal switch sits inside the Chat screen and must retain chat state; the terminal input may operate on current-chat scope. Opening the global Wallet terminal may change default scope. `chat.background.change` with no parameter opens a background picker. Chat visual theme and terminal chrome theme are separate settings.

## Authorization

- `.read`: read-only action (still scope data to the authenticated user)
- `.write`: safe in-app updates; preview on ambiguity
- `.sensitive`: do not execute until app-specific explicit confirmation. Wallet sends require network/address/fee review and cryptographic authorization. Bulk messages require recipient review and rate limits.

`TerminalMatch.needsConfirmation` only labels risk; production safety is enforced by the host Action Router. Never rely on client-side risk flags alone.

## App Store

Check https://developer.apple.com/app-store/review/guidelines/ (especially §§2.5.2 and 4.7) before enabling third-party scripts, downloaded code, or mini apps. Interpreted code cannot be treated as a free pass to add arbitrary native-app capabilities after review.
