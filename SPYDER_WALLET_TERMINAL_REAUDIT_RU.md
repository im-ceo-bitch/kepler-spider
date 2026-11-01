# Spyder Wallet + Terminal — повторный аудит (01.11.2026)

База: `kepler-spider-main 3.zip`, затем накопительный Wallet + Terminal.

Найдены и исправлены реальные Swift API-ссылки, которые прежние статические тесты не проверяли:

1. `SpyderChatTerminalView.swift` вызывал отсутствующий в `SpyderChatStore` метод `updateDisplayName`. API изменения имени отсутствует также на сервере Chat v2. Команда теперь объясняет недоступность функции, не заявляя об успешном изменении.
2. `SpyderSonicPlayer` вызывался в `ChatDetailView.swift` и `SpyderChatTerminalView.swift`, но не определён ни в репозитории, ни в подключённых пакетах. Заменено на системный тактильный сигнал `UINotificationFeedbackGenerator` после успешной отправки. Звуковой эффект не реализован.
3. Добавлены регрессионные тесты `ci/tests/test_terminal_wallet_build_symbols.py` на эти ошибки.

Повторно выполнены на наложенной копии репозитория:
- Python CI: 66/66
- Дополнительные Python: 21/21
- SpyderTerminalKit Swift package tests: 16/16
- Chat сервер: 15/15
- MessageChain: 7/7
- `swiftc -frontend -parse` всех Swift-файлов: успешно
- `ci/verify_repo.py`: успешно
- RU/EN `.strings` plist: успешно
- Целостность ZIP и наложение обновления: успешно

**Ограничение:** Xcode 26.6, XcodeGen и iOS SDK в этой Linux-среде отсутствуют. Полный `xcodebuild archive` здесь НЕ выполнялся. Поэтому этот ZIP нельзя считать подтверждённым TestFlight-релизом до успешного build-only CI на macOS. Проверка не гарантирует отсутствие других SwiftUI typecheck/SDK/signing ошибок.

Обновление не изменяет облачный сервер Chat v2, Wallet Vault и обработку seed-фраз.
