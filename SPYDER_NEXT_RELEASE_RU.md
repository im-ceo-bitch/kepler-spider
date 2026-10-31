# Spyder Wallet — Mainnet Read-Only + Username Chat

## Что реально добавлено

- Настоящие mainnet-балансы ETH (Ethereum JSON-RPC), SOL (Solana RPC), BTC (Blockstream Esplora).
- Настоящие балансы USDT ERC-20 и USDC ERC-20 (только Ethereum) через `eth_call(balanceOf)`. Сети и контракты зафиксированы по официальным данным эмитентов.
- Публичные цены BTC/ETH/SOL в USD (CoinGecko). Долларовая сумма в шапке учитывает три нативные монеты, **не** USDT/USDC. При недоступности любой из трёх сетей итог не показывается вместо ложного нуля.
- Ссылки на обозреватели цепей, QR и копирование адресов для получения.
- Реальный Spyder Chat вместо устаревшей вкладки Console: регистрация `@username`, поиск, заявки по username, подтверждение контакта, переписка 1:1, сохранение истории на собственном Cloudflare Worker.
- Миграция старого устройства чата: можно назначить username, не теряя старого ID и приглашения.

## Важные ограничения

- **Реальную отправку BTC/ETH/SOL/USDT/USDC не включали.** Для неё нужно безопасно реализовать подпись транзакций, расчёт комиссий, проверку nonce/UTXO и симуляцию в тестовых сетях. Кнопка Send пока относится к SPD Devnet.
- Чат **не использует E2EE**: сообщения доступны оператору твоего Worker. Не передавай seed и финансовые секреты в чате. Функции доступны только после реального развёртывания сервера, которого этот ZIP выполнить не может.
- Внешние публичные RPC не имеют SLA и могут вернуть HTTP 429/403. Для production и платежей нужны выделенные узлы / собственная инфраструктура.
- Никаких реальных средств на новый неподтверждённый кошелёк до независимого аудита и испытаний восстановления; сначала проверь отображение на известных публичных адресах и тестовые переводы.
- Профиль чата привязан к локальному Keychain конкретного iPhone. Восстановление чата на новом устройстве ещё не поддерживается.

## Установка (первый раз)

1. Загрузи `console-update-spyder-mainnet-chat-v1.zip` в **корень** `kepler-spider` через GitHub. Дождись зелёного `Console — Auto Unpack Update`.
2. В Secrets репозитория должны быть `CLOUDFLARE_API_TOKEN` и `CLOUDFLARE_ACCOUNT_ID` (токен должен иметь разрешения Workers Scripts и Durable Objects). Запусти **Console — Deploy Realtime Server** вручную в GitHub Actions — commit от unpack-бота не запускает следующий workflow автоматически.
3. Из лога деплоя возьми публичный HTTPS URL Worker вида `https://spyder-chat-devnet.<subdomain>.workers.dev`. Проверь открытием `<URL>/health`: должен быть `service=spyder-chat-devnet`, `version=1`.
4. Добавь в GitHub Actions Secret `SPYDER_CHAT_SERVER_URL` **только полный HTTPS URL Worker**. Имя секрета точно такое. Он подставляется в `Info.plist` при сборке приложения, не в исходный Swift.
5. Для автоматической подстановки URL замени текущий `.github/workflows/spyder-wallet-testflight-cloud.yml` на отдельный прилагаемый файл `spyder-wallet-testflight-cloud.yml`. Не загружай YAML в распаковщик: он защищает `.github/workflows` и пропустит этот путь.
6. Запусти TestFlight Cloud Signing. Маркетинговая версия **остаётся 1.0** и изменяется вручную в `project.yml`; build number — `github.run_number` у существующего workflow. **Не создавай новый workflow с другим именем, иначе счётчик может начать новую последовательность**.
7. На двух iPhone зарегистрируй разные `@username`; на одном найди второй по username, отправь приглашение, на другом прими и отправь сообщение. Для старых профилей назначь username во вкладке Chats.

Если Cloudflare пока не развёрнут или секрет не задан, кнопка регистрации покажет поле HTTPS сервера для ручной настройки. Приложение не будет выдавать ложное «подключено».

## Тесты

- `npm --prefix server run check` — backend API + регистрация, уникальность username, поиск, приглашения, сообщения.
- `python3 -m unittest discover -s ci/tests -v` — регрессии проекта.
- `node --test MessageChain/tests/*.test.mjs` — крипто/сетевой код.
- `swiftc -frontend -parse $(find Console Tests -name '*.swift')` — **только** синтаксический анализ Swift; **не** полноценная Xcode сборка.

Обновление не выдаётся как проверенное на iOS-устройстве: в этой среде нет Xcode, Apple signing и доступа к Cloudflare аккаунту. Обязательно сначала проверь реальные логи GitHub Actions и наличие новой сборки в App Store Connect/TestFlight.
