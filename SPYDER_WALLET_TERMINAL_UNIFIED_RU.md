# Spyder Wallet + Terminal — единый накопительный патч

Объединены два оригинальных ZIP:

- `console-update-spyder-wallet-cumulative-control-v2-20261101.zip`
- `console-update-spyder-terminal-v1.zip`

Оба архива имеют общие файлы `Console/WalletRootView.swift` и `project.yml`.
В этом обновлении они **объединены вручную**, а не выбраны по принципу «последний файл побеждает».

### Что сохранено

- Wallet Control Center, Security Center, аккаунты и адресная книга.
- Wallet Portfolio, LIVE-графики, каталог топ-250, RU/EN, история операций.
- Совместимая маршрутизация Chat Unified, APNs, push-переход в чат.
- Spyder Terminal Kit, переключатель Чат/Терминал, команды RU/EN, настройки терминала, темы чата.
- Защитные ограничения: неподготовленные Mainnet-отправки остаются заблокированными; исполнение произвольного JavaScript не включено.

В `project.yml` добавлена зависимость от локального `SpyderTerminalKit`; пакет содержит собственные ресурсы и тесты.
В `WalletRootView.swift` сохранены все маршруты Control Center и добавлен callback `onOpenActivity` для терминала.
Профиль маршрутизируется в `WalletSettingsView()`, где есть доступ к настройкам терминала. Незавершённый `SpyderIdentityHubView` не используется.

### Проверки (Linux, без macOS SDK)

- 63/63 Python CI теста.
- 21/21 дополнительных Python тест.
- 16/16 unit-тестов Swift Package SpyderTerminalKit.
- 15/15 серверных тестов Node.js.
- 7/7 тестов MessageChain.
- Swift parse исходников, структура пакета, проверка ZIP и наложение на доступный `kepler-spider-main 3.zip`.

**Ограничение:** полноценный `xcodebuild` для iOS, SwiftUI typecheck с Apple SDK и TestFlight в этой среде не выполнены.
Данные проверки не подтверждают production-готовность; сначала запустите build-only CI и затем TestFlight.

### Установка

Положите **только этот ZIP** в корень GitHub, распакуйте существующим workflow `console-update*.zip`.
Предыдущие два ZIP отдельно устанавливать не нужно.
ZIP не содержит каталога-обёртки и не перезаписывает `.github/workflows`.

Патч сформирован относительно предоставленного `kepler-spider-main 3.zip` и известной цепочки обновлений.
Если в `main` уже есть другие непроверенные изменения тех же файлов после этой цепочки, потребуется повторное сравнение с фактическим `main`.
