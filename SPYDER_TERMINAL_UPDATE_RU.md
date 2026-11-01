# Spyder Terminal — интеграция iOS (patch v1)

## Как установить

Загрузите `console-update-spyder-terminal-v1.zip` в КОРЕНЬ GitHub-репозитория Spyder Wallet. Текущий `.github/workflows/console-auto-unpack.yml` автоматически распакует файл поверх исходников, не трогая workflows. ZIP не содержит внешней папки `kepler-spider-main` и не заменяет несвязанные исходники.

Xcode-проект генерируется существующим CI из `project.yml`: добавлена локальная зависимость `Packages/SpyderTerminalKit`. Не нужно создавать дополнительный GitHub workflow или Secrets.

## Что подключено

- `Console/Features/Chats/ChatDetailView.swift`: переключатель «Чат | Терминал» над перепиской. Состояние переписки не сбрасывается. История команд остаётся в памяти открытого экрана.
- `Console/Features/Chats/SpyderChatTerminalView.swift`: полноценная панель терминала и маршрут выполнения только разрешённых операций.
- `Console/Features/Chats/SpyderChatExperience.swift`: Chrome и Thunder реализованы нативным Canvas, Cyberpunk использует существующий Cyber-фон. Все темы доступны и из настроек оформления чата.
- `Console/Features/Settings/WalletSettingsView.swift`: доступ к настройкам терминала из общих настроек.
- `Console/WalletRootView.swift`: штатная навигация терминала к истории операций.
- `Packages/SpyderTerminalKit/`: 28 эквивалентных Action ID в JSON RU/EN; парсер, настройки, подсказки после 2–3 символов и тесты.

### Примеры

`сп измени фон` = `sp change background` — открывает стандартный выбор фонов.
`сп измени тему на Chrome` = `sp change theme to Chrome` — сразу меняет фон именно текущего чата.
`сп измени тему чата на киберпанк` = `sp change chat theme to cyberpunk`.
`сп покажи баланс` = `sp show balance` — показывает *только реально полученные* WalletPublicAssetsStore балансы; в privacy mode данные скрыты.
`сп покажи контакты` = `sp show contacts`.
`сп измени имя на ...` = `sp change name to ...` — вызывает существующий защищённый API профиля.
`сп отправь Привет` = `sp send Hello` — использует чат E2EE после явного подтверждения текста.
`сп настройки терминала` = `sp terminal settings`.

### Ограничения, заявленные явно

- Beginner: локальное распознавание набора естественных фраз, НЕ AI-обработка произвольных предложений. Для свободного NLU в будущем нужен безопасный распознаватель.
- Developer: UI и режим предусмотрены, произвольный JavaScript **не выполняется**, чтобы не выдавать небезопасный runtime за готовый.
- `wallet.send` и `chat.broadcast` распознаются, но никогда не выполняются без отдельной реализации проверок и разрешений.
- Остальные распознаваемые, но пока не подключённые действия сообщают об этом, вместо фиктивного «готово».
- История терминала хранится только в памяти открытого чата, не переносится в другое устройство, не сохраняется в UserDefaults, не содержит исходные чувствительные команды.
- Темы Chrome / Thunder — нативные Canvas-фоны, не полноценные наборы UI-тем сообщений.
- Xcode и iOS SDK в Linux окружении отсутствуют: проведены синтаксический разбор Swift, Linux `swift test` и существующие проверки CI. Реальный `xcodebuild` для iOS должен выполняться на macOS.

## Контроль качества

- `cd Packages/SpyderTerminalKit && swift test`
- `python3 ci/verify_repo.py`
- `python3 -m unittest discover -s ci/tests -q`
- В macOS CI: `xcodegen generate --spec project.yml` и build-only `xcodebuild -project Console.xcodeproj -scheme Console -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`

Для проверки UI на физических устройствах: iPhone 11 / iPhone 13 mini, экран при открытой клавиатуре, светлая/тёмная тема, safe areas, возврат Чат↔Терминал, сохранение настроек, E2EE отправка.
