# Spyder Wallet — LIVE Dual Theme + Chat Unified (совместимая версия)

Назначение: заменить исходный `console-update-spyder-wallet-live-dual-theme-20261101.zip`,
который перезаписывал часть интеграции Chat Unified.

## Установка

1. В `main` должен быть уже распакован `console-update-chat-unified-20261101.zip`.
2. Загрузите **только этот** ZIP `console-update-spyder-wallet-live-dual-theme-chat-compatible-20261101.zip`
   в корень репозитория GitHub. Дождитесь завершения распаковщика.
3. Запустите build-only CI, затем TestFlight только после успешной сборки.
4. Не загружайте старый `console-update-spyder-wallet-live-dual-theme-20261101.zip` после этого патча.

## Что объединено

- `Console/ConsoleApp.swift`: APNs delegate, регистрация push-токена и обработка
  ошибок сохранены из Chat Unified; WalletMarketStore, WalletLiveMarketStore,
  live-котировки и остановка WebSocket в фоне добавлены из Wallet LIVE.
- `Console/WalletRootView.swift`: переход в чат по push сохранён;
  обычное получение криптовалюты открывает Ethereum, а не тестовую сеть.
- `ci/tests/test_spyder_live_release.py`: проверка чата адаптирована к
  маршрутизации Chat v2 из `server/src/index.mjs` и настоящей сигнатуре
  `chat.register` с настройкой публичности.
- `ci/tests/test_chat_wallet_overlay_compat.py`: новый контроль двух интеграций.

Новые версии Chat-сервера, APNs delegate, entitlements, ChatService, чатов и
`project.yml` **не заменяются** этим патчем и остаются из Chat Unified.

## Контроль качества

Проведены локальные Python CI, Node server и MessageChain тесты,
Swift-синтаксический parse и тест целостности ZIP. Полная компиляция
Apple SwiftUI / Xcode и проверка APNs на настоящем устройстве не выполнялись.
Нельзя объявлять патч production-проверенным до зелёного build-only CI.
