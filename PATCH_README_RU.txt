Spyder Wallet — Chat compile compatibility hotfix v0.5.6

Устраняет ошибки SwiftCompile из GitHub Actions 29.10.2026:
ChatsHomeView.swift:155,158,168 — отсутствующие probeServer, checkingServer, serverStatus в SpyderChatStore.

Изменяет только Console/ChatLive/SpyderChatService.swift.
Добавлены два Published-состояния и async probeServer() для /health.
Сохранены клиент чата, настройки Apple, Bundle ID и существующий workflow.

Проверено:
- 27 Swift-файлов собранного дерева предыдущих патчей: swiftc -frontend -parse PASS.
- Согласованность всех 15 вызовов chat.* на ChatsHomeView с API SpyderChatStore PASS.
- Node серверный тест чата 1/1 PASS.
- ZIP integrity PASS.

ВАЖНО: нет macOS/Xcode; реальная Xcode сборка не выполнялась. Этот патч снимает доказанный конфликт API, но нельзя считать релиз подтвержденным до зеленого build-only на macOS.

Установка: через существующий распаковщик загрузить ZIP в корень репозитория kepler-spider. Не менять workflow. Сначала запустить build_only=true и проверить Debug/Release; при успехе отдельно запускать TestFlight upload. Не удалять приложение / Keychain.
