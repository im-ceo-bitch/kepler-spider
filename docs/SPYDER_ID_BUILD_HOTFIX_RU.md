# Spyder ID — исправление сборки 15.11.2026

Основа: kepler-spider-main.zip и logs_118284797785.zip. Последний TestFlight остановился на `Verify source and run unit tests` (166/167 успешно), до XcodeGen/архивации. Ошибка: устаревшая регулярка `test_market_has_explicit_navigation_and_wallet_actions_remain_visible`, не учитывавшая карточку Spyder ID. Не удалены карточка, тест или проверка порядка компонентов.

## Изменения
- CI: проверка порядка WalletHomeView учитывает Spyder ID.
- Preflight: проверка App Group, Keychain group, отдельных Bundle ID, версий, встраивания расширений, AutoFill capabilities и ресурсов Safari.
- AutoFill: недопустимые домены никогда не совпадают даже при двух nil; добавлен XCTest.
- Passkeys XCTest: длинное выражение Data + Data разбито на append без изменения ожидаемых байтов.
- Исторические тесты в tests/: исправлен неверный путь до корня и актуализированы проверки перенесённого аватара и авторизованных USDT-переводов. Продакшн-код платежей не изменён.

## Установка
1. Загрузить только `console-update-spyder-id-build-fix.zip` в корень текущего репозитория.
2. Дождаться успешного Console — Auto Unpack Update и коммита распаковщика.
3. В существующем TestFlight workflow рекомендуется вручную убрать единственную строку `PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \` из вызова `xcodebuild ... archive`. ID всех четырёх целей уже определены в project.yml, а ID расширений также закреплены в Info.plist. Глобальный override создаёт риск для сборки/подписи расширений. Workflow не входит в ZIP; распаковщик защищает `.github/workflows`.
4. Проверить в Apple Developer наличие App ID com.spyder.wallet, com.spyder.wallet.id.autofill, com.spyder.wallet.id.safari, com.spyder.wallet.id.share; общая группа group.com.spyder.wallet.id назначена всем, AutoFill Credential Provider включён у основного приложения и AutoFill. Не менять Apple Team или ключи без необходимости.
5. Запустить обычный TestFlight workflow. Дополнительно проверить, что в архиве три PlugIns/*.appex с разными ID и совпадающими с основным приложением версиями/номерами сборки.

## Проверки в текущей среде
- `python3 ci/verify_repo.py` — OK.
- `python3 -m unittest discover -s ci/tests -v` — 167/167 OK (после изменений).
- `python3 -m unittest discover -s tests -v` — 31/31 OK.
- `node --test MessageChain/tests/*.test.mjs` — 7/7 OK.
- `swiftc -frontend -parse -swift-version 5` — 147 Swift-файлов Console, Shared, Extensions, Tests; OK.
- `node --check` для двух JS-файлов Safari — OK.
- Safari DOM-тесты не запущены: в среде отсутствует jsdom. Xcode typecheck/archive, XCTest, signing/export, Simulator и iPhone не запущены: среда Linux, без Apple SDK. Поэтому гарантировать успешный TestFlight до запуска macOS CI нельзя.
