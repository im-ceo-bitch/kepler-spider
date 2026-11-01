# Spyder Terminal — накопительное обновление v3 (01.11.2026)

## Основа
`kepler-spider-main 3.zip`, пользовательский архив от 01.11.2026.

## Установка
Загрузить **один** ZIP `console-update-spyder-terminal-chat-v3.zip` в корень репозитория.
Действующий `.github/workflows/console-auto-unpack.yml` определит файл `console-update*.zip` и наложит файлы поверх `main`. В архиве нет внешней папки, `.github/workflows` и сторонних изменений.
Ни в коем случае не накладывать на старую версию `main`, отличающуюся от исходного ZIP, без сравнения изменённых файлов.

## Реальные изменения
- Единый переключатель Chat | Terminal уже был в репозитории и **сохранён**. В активном `SpyderTerminalChatContainer` теперь доступны реальные обработчики оформления Chrome / Cyberpunk / Thunder, контактов, поиска по текущим загруженным сообщениям, профиля, приватного баланса, экрана получения и истории операций, темы и языка приложения.
- `сп измени фон` и `sp change background` открывают существующую панель выбора фона; `сп измени тему на гром` и `sp change theme to Chrome` меняют оформление текущего чата и оповещают открытый ChatDetailView.
- `сп отправь ...` / `sp send ...` используют E2EE `SpyderChatStore.sendMessage` **только после отдельного предпросмотра и подтверждения**; проверяется текущий peer, авторизованная личность, контакт и готовность E2EE. Текст сообщения не сохраняется в истории команд.
- Исправлена связь WalletHomeView с Control Center, а также маршруты Security / AddressBook и WalletAddressBookStore environmentObject (ранее отсутствовали в исходном архиве).
- Сохранены разделение ключей Wallet и Chat, существующие push/APNs, работа seed/Wallet Vault, протоколы сети и Cloudflare backend. Существующие `.github/workflows` не менялись.
- Массовые отправки и криптопереводы **не включены**: зарегистрированного обработчика нет. Изменение имени профиля сервер Chat v2 не поддерживает. Свободный Beginner ограничен локальным набором фраз, JS Developer не исполняется.

## Проверки в данной среде (Linux)
- `swift test` локального SpyderTerminalKit: 26/26 успешно.
- Синтаксический разбор Swift (`swiftc -frontend -parse`) для исходников и пакета: успешно. **Это не Xcode typecheck или iOS build**.
- `python3 ci/verify_repo.py`: успешно.
- `python3 -m unittest discover -s ci/tests -q`: 85/88; 3 исходных несоответствия в старых регрессионных проверках Sonic Push и Wallet Avatar остаются, не менялись этим патчем.
- `server`: 15/15 node tests, `MessageChain`: 7/7 node tests.
- Проверка ZIP, безопасных путей и наложения поверх предоставленного репозитория: пройдена.

## Нужна проверка на macOS
`xcodegen generate --spec project.yml` -> `xcodebuild -project Console.xcodeproj -scheme Console -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`.
Только после успешной сборки и QA iPhone 11 / 13 mini запускать TestFlight.
