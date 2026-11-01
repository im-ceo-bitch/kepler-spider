# Исправление компиляции терминала — 2026-11-02

Основание: GitHub Actions run `112045891543`, commit `e52125057798476ee4a335660dcd7cfc1e9a607d`.

1. `SpyderChatTerminalView.swift`: полная обработка `TerminalAppearance.light` без изменения режима работы терминала (весь терминал по-прежнему принудительно тёмный для контраста).
2. `ChatDetailView+TerminalLegacyInit.swift`: отдельный совместимый инициализатор для старого `SpyderTerminalChatContainer`, вызывающего ChatDetailView без `onOpenActivity`. Основной путь WalletRootView продолжает передавать работающий callback истории, а старый wrapper напрямую исполняет callback истории через свой зарегистрированный TerminalActionHost. Вложенный локальный fallback не открывает историю при использовании этого старого вызова.

Не заменяет `SpyderTerminalChatContainer.swift`, сохраняет его новые обработчики, сервер, E2EE, Personas, APNs, Wallet и Package без изменений.

Проверки: два прохода (исходники + распаковка ZIP), Swift Parser, standalone type-check fixtures, базовые тесты TerminalKit. Полный Xcode Archive здесь недоступен; необходимо выполнить новый build-only CI.

Имя ZIP: `console-update-spyder-terminal-switch-activity-fix-20261102.zip`.
