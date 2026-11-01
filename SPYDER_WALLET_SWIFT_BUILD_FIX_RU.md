# Spyder Wallet — исправление Xcode compilation (2026-11-01)

Источник: `logs_111911102907.zip`, Xcode 26.6, шаг `Compile and archive iOS Release`.

## Точные ошибки и изменения

- `Console/WalletCore/WalletActivityHistory.swift:95` — неоднозначная передача `Decimal.init(string:)` в `Optional.flatMap`. Заменено явным замыканием с фиксированной POSIX locale.
- `Console/WalletCore/WalletActivityHistory.swift:141` — бросающий `decodeNil` внутри логического `&&` без корректного `try`. Разделено на `if` и безопасное декодирование.
- `Console/Features/Wallet/WalletHomeView.swift:412` — `.font` применялся к управляющей конструкции `if`, а не `Text`. Модификаторы перемещены внутрь ветки.
- `ci/tests/test_wallet_compiler_regressions.py` — добавлена проверка реальным Swift-компилятором `-typecheck` из CI (при наличии `swiftc`), а также проверка SwiftUI-модификаторов. Штатные архив и TestFlight workflow не меняются.

## Проверка

Целевая модель установлена поверх исходного репозитория + Block 1–2 + Block 3–4 Build Fix. Linux Swift 6.2.1 типизирует весь `WalletActivityHistory.swift` с минимальными заглушками внешних зависимостей и с `FoundationNetworking` только для Linux. Все Swift файлы разбираются синтаксически. Полную компиляцию приложения с Apple SwiftUI и Xcode в Linux выполнить невозможно.

## Установка

Загрузить единственный архив `console-update-spyder-wallet-swift-buildfix-20261101.zip` в корень репозитория и дождаться успешного unpack. **Другие архивы не загружать повторно.** Убедиться, что исправленные файлы появились в `main`, затем запустить TestFlight. В случае новой ошибки приложить полный GitHub Actions log.

Изменения не затрагивают seed-фразы, Keychain, протокол чатов, криптографические операции, настройки сертификатов или GitHub Secrets.
