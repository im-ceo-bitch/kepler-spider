# Spyder Wallet — Production foundation / cumulative 1B

База: `kepler-spider-main.zip`, commit `402ad44162214430e752667f896d9668f1fd8cbe`.

Этот архив **накопительный**: включает все файлы патча Production Foundation 1A (который ещё не был установлен в GitHub) и дополнительное исправление 1B. Устанавливать нужно только этот архив, не накладывая отдельно предыдущий `console-update-production-block1a.zip`.

## 1A — security foundation
- Защита от запоздалого Face ID callback после блокировки и повторных параллельных попыток.
- EIP-55 checksum для mixed-case Ethereum адресов, отказ для нулевого адреса.
- Проверка адреса перед EVM signing и точное сравнение Solana адресов в адресной книге.
- Сброс USDT approval при смене активного аккаунта.
- Исправление reentrancy гонки в test-only broadcast staging.
- Регрессионные тесты для указанных сценариев.

## 1B — Wallet Vault account-index ordering
Ранее `WalletVault.save` сначала записывал seed в Keychain, а затем обновлял индекс аккаунтов. Если запись индекса завершалась ошибкой, seed мог остаться в Keychain, но не попасть в индекс обнаруживаемых аккаунтов.

Теперь:
1. Публичный UUID аккаунта резервируется в Keychain account index.
2. После успешной записи индекса добавляется seed item.
3. Если запись seed item не удалась, выполняется откат резервирования UUID.
4. Если процесс завершится между резервированием и записью seed, `WalletAccess` фильтрует такой stale ID через `WalletVault.exists(id:)`.

Изменение не меняет Keychain service/account identifiers, BIP-39 формат, derivation paths, доступность seed item (`WhenPasscodeSetThisDeviceOnly` + `userPresence`) и не переносит секреты в UserDefaults.

## Проверки
- Целевые тесты Wallet Vault, security foundation, address book и EVM broadcast staging: 13 passed.
- `swiftc -frontend -parse` изменённых Swift production-файлов: успешно.
- Полный `pytest -q ci/tests`: 182 passed, 2 failed, 11 subtests passed. Два известных сбоя — `test_spyder_terminal_v2_integration.py`: тест ожидает зависимость `SpyderTerminalKit` в `project.yml` и прямой вызов `SpyderTerminalChatContainer` в `WalletRootView`, тогда как текущая конфигурация исключает контейнер и использует `SpyderConversationSession`. Это не исправлялось маскировкой тестов.
- Xcode build, iOS Simulator, физическое устройство, Face ID/Keychain runtime и live RPC в этой Linux-среде не запускались.

## Установка
Загрузить этот ZIP в корень GitHub-репозитория. Использовать существующий console-auto-unpack workflow. YAML/workflows в архив не включены. После распаковки проверить GitHub Actions и выполнить macOS Xcode build. Это не разрешение на mainnet-переводы или production release.
