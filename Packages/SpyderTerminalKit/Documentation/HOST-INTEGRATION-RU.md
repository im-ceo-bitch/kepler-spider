# Spyder TerminalKit v2 — подключение к существующему Spyder Wallet

**Статус:** SDK + готовый нативный контейнер + bridge для вызова **реальных сервисов приложения**. Пакет НЕ является обновлением существующего репозитория `kepler-spider-main`: актуальный исходник приложения не предоставлен. Он не содержит замены файлов приложения, не выполняет криптовалютных переводов самостоятельно и не гарантирует сборку TestFlight.

## Состав v2

- `SpyderChatTerminalSwitchView` — встраивается вокруг существующего экрана переписки; визуально разделяет «Чат» и «Терминал», не уничтожая поддерево чата при переключении.
- `SpyderTerminalInputView` — 2/3-символьное автодополнение, двухъязычный парсер, редактор команды.
- `SpyderTerminalSettingsView` — настройки режима, языка, подсказок, темы, акцента, шрифта и истории.
- `TerminalActionRegistryHost` — адаптер к существующим сервисам с явной регистрацией каждого действия; незарегистрированные команды завершаются ошибкой.
- `TerminalExecutionGate` — отдельный preview + одноразовое подтверждение для `risk=sensitive` (например, перевод, массовая рассылка), запрет повторного подтверждения, истечение спустя 90 секунд, отмена устаревшего preview.
- `TerminalActionContext` — ID авторизованного аккаунта и текущего чата передаются из приложения, никогда из текста пользователя.

## Подключение

1. Подключите каталог пакета как **Local Swift Package** к приложению. Назначьте `SpyderTerminalKit` основному iOS target.
2. В composition root (DI) создайте *стабильный* экземпляр `TerminalActionRegistryHost`.
3. Вызовите `register` для каждого поддерживаемого действия, используя **существующий** менеджер переписок, тем, профиля или кошелька. Не создавайте вторую независимую базу чатов.
4. Оберните исходный контент переписки в `SpyderChatTerminalSwitchView`; передайте `accountID` и `conversationID` из авторизованной сессии.
5. Проверьте навигацию и safe areas на iPhone 11 и iPhone 13 mini, тёмную и светлую тему, жесты, клавиатуру и нижнюю панель.
6. Выполните **на Mac в Xcode** полноценную сборку приложения до запуска TestFlight. Linux `swift test` не проверяет компиляцию SwiftUI.

## Код привязки действий

```swift
import SpyderTerminalKit

// Внедрите host как стабильный объект в состояние приложения.
@MainActor
func makeTerminalHost(services: ExistingAppServices) throws -> TerminalActionRegistryHost {
    let host = try TerminalActionRegistryHost()

    try host.register("chat.theme.set") { req in
        guard let theme = req.parameters["theme"],
              ["chrome", "cyberpunk", "thunder"].contains(theme) else {
            throw TerminalHostError.invalidParameter("theme")
        }
        // Вызов РЕАЛЬНОГО существующего метода приложения.
        try await services.chatThemes.set(theme, conversationID: req.context.conversationID)
        return TerminalActionResult(message: "Theme changed: \(theme)")
    }

    try host.register("chat.background.change") { req in
        // Открыть существующий picker через роутер приложения.
        services.navigation.openChatWallpaperPicker(conversationID: req.context.conversationID)
        return TerminalActionResult(message: "Choose a background")
    }

    try host.register("wallet.balance") { req in
        let balance = try await services.wallet.readBalance(accountID: req.context.accountID)
        return TerminalActionResult(message: balance.formattedDescription)
    }

    try host.register("chat.broadcast", execute: { req in
        // Проверка контактов и антиспам-ограничений ОБЯЗАТЕЛЬНА повторно.
        try await services.messaging.broadcastAuthenticated(req)
        return TerminalActionResult(message: "Broadcast submitted")
    }, review: { req in
        let review = try await services.messaging.reviewBroadcast(req)
        // Из backend: количество, список получателей, содержание рассылки.
        return TerminalActionPreview(title: review.title, details: review.details)
    })

    return host
}
```

`ExistingAppServices`, `services.chatThemes`, `services.wallet` и `services.messaging` — **схематические имена существующих сервисов**, которые нужно заменить реальными API после просмотра `kepler-spider-main`. Пример намеренно не содержит ложной реализации операций.

Пример экрана:

```swift
import SwiftUI
import SpyderTerminalKit

struct ConversationWithTerminal: View {
    let host: TerminalActionRegistryHost
    let currentAccountID: String
    let currentChatID: String

    var body: some View {
        SpyderChatTerminalSwitchView(
            context: .init(conversationID: currentChatID, accountID: currentAccountID),
            host: host
        ) {
            ExistingConversationContent() // Уже существующий чат — без изменений.
        }
    }
}
```

## Важные гарантии и ограничения

- **Действие = один Action ID**, независимо от `сп` / `sp`.
- **Начинающий:** словарные вариации фраз уже работают, но произвольный естественный язык требует NLU-интеграции.
- **Standard:** только зарегистрированные шаблоны.
- **Developer:** при вводе JavaScript показывается сообщение, что runtime пока не подключён. Код НЕ исполняется.
- **Область безопасности:** регистрация действия — это не разрешение пользователя; обработчики `services` ОБЯЗАНЫ снова проверить авторизацию, права и актуальность параметров.
- **Транзакции:** preview отображает подтверждённые backend-параметры (актив, сумма, адрес, сеть, комиссия), затем приложение запрашивает необходимую криптографическую подпись отдельным процессом.
- **История:** в v2 история команд только в памяти текущей сессии (до 100 записей), без записи приватных сообщений в `UserDefaults`.
- **Тесты:** 21 Swift XCTest на Linux, включая обработку правок и блокировку критичных операций. Полного Xcode build iOS приложения нет.

## Что требуется для точного накопительного патча

Актуальный архив основного репозитория `kepler-spider-main` или доступ к его фактическому `main`; после получения можно проверить дерево проекта, существующие `View`, API менеджеров, Xcode project/Package references, интегрировать без конфликта и выдать компактный ZIP для существующего распаковщика.
