# Spyder Terminal Kit v2 — совместимое накопительное обновление

## Назначение

Это адаптированная версия `spyder-terminal-kit-v2-integration-ready.zip` для существующего распаковщика `console-update*.zip`. Пакет размещён в `Packages/SpyderTerminalKit/`, а не поверх корневых `README.md`, `Tests/` или `Sources/`. Следовательно, исходные файлы кошелька, E2EE, APNs, AutoConnect и Top-250 не подменяются.

## Что подключено

- `SpyderTerminalKit` как **локальная Swift Package** в `project.yml` (XcodeGen).
- Переключатель «Чат | Терминал» в существующей переписке — без замены её содержимого.
- Команды `profile.show`, `contacts.list`, `network.status` вызывают только существующий `SpyderChatStore`.
- `chat.background.change` открывает существующий выбор оформления переписки; изменения отображаются в чате после закрытия.
- `terminal.help`, `terminal.settings.open`, `terminal.mode.set`, `terminal.history.open` выполняются внутри SDK.
- Остальные команды намеренно **не зарегистрированы**, поэтому показывают отказ вместо фиктивного успеха, особенно для денежных переводов, рассылок и отправки сообщений.
- Начальная вкладка — обычный чат, история сообщений, E2EE, Spyder Sonic, настройки и рыночный кошелёк не меняются.

## Проверка перед TestFlight

1. В корне репозитория должен находиться **ровно один** `console-update*.zip`. Не загружай исходный `spyder-terminal-kit-v2-integration-ready.zip` дополнительно.
2. Дождись завершения `Console — Auto Unpack Update`.
3. Проверь, что `Packages/SpyderTerminalKit/Package.swift` существует, а `project.yml` содержит соответствующую зависимость.
4. Выполни **build-only CI/Xcode build**. Отдельно проверь экран переписки и переключатель, затем TestFlight.

## Оговорки

21 unit-тест SDK проходят на Linux. iOS SwiftUI-компоненты, сборка XcodeGen и полный Xcode build на macOS пока **не подтверждены**. Дополнительно запрещены сетевые финансовые действия в терминале, пока не будет реализована проверяемая привязка хост-сервисов и повторная авторизация.

Пути внутри ZIP рассчитаны на фактическую логику `.github/workflows/console-auto-unpack.yml`: архив имеет несколько корневых элементов, поэтому распаковщик **не отрезает папку `Console`**.
