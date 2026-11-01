# Spyder Network: Stage 1 (APNs + Sonic) / Stage 2 (Spyder ID)

Сборка: накладывать после `console-update-chat-unified-20261101.zip` и существующего Motion Kit.
ZIP содержит файлы относительно корня репозитория, workflow не изменяются.

## Что включено

- Собственные звуки **Spyder Pulse** (`spyder_receive.caf`), **Spyder Whisper** (`spyder_sent.caf`) и **Spyder Connect** (`spyder_connect.caf`) — PCM 32 kHz, менее одной секунды. Написаны и синтезированы специально для Spyder; это не звуки iMessage.
- Уведомление от APNs содержит только нейтральный текст и выбранный звук, без текста чата.
- Экран **Spyder ID → Уведомления и звуки**: включение APNs, выбор `Spyder Pulse` / системный / без звука, локальный звук отправки, предпросмотр, три уровня диагностики и тестовое push-событие.
- GET `/v2/push/status`: `provider_ready`, `enabled`, `sound`, `last_apns_status`, `last_attempt_at`; без раскрытия device token.
- POST `/v2/push/preferences`: защищённый выбор звука, только после регистрации APNs.
- POST `/v2/push/test`: авторизованный тест только своего устройства, максимум 3 раза в час, статус `queued` — **не подтверждение доставки**.
- POST `/v2/profile/name`: сохранение имени на сервере и в локальной chat identity через Keychain только после ответа сервера. Существующий `/v1/profile/username` сохранён.
- Объединённая страница **Spyder ID** из кошелька и «Сети»: анимированный аватар, `@username`, QR-код из публичного имени, ShareLink, приватность поиска, настройки звука, оформление и защищённые настройки кошелька.
- Мультипрофильность **не имитируется**: сервер и Keychain по-прежнему реализуют один чат-аккаунт на устройство.

## Безопасный порядок запуска

1. Успешно распаковать патч поверх актуального `main` и убедиться, что изменились только файлы из ZIP.
2. Запустить тесты `cd server && npm test` и `python -m unittest discover -s ci/tests -p 'test_*.py'` и `python -m unittest discover -s tests -p 'test_*.py'`.
3. Проверить, что GitHub Secret `CLOUDFLARE_API_TOKEN` — одна строка без переносов и что Worker **kepler-spider** содержит оба `MESSAGE_ROOMS`, `CHAT_HUB`; не удалять ни один.
4. Запустить `Console — Deploy Realtime Server`; успешный Wrangler deploy необходим для новых маршрутов.
5. В TestFlight поставить новую версию. Проверь `aps-environment=production` и, что `spyder_receive.caf` / `spyder_connect.caf` включены в Copy Bundle Resources.
6. На iPhone B: **Сеть → профиль → Уведомления и звуки → Сообщения и приглашения**. Разрешить уведомления iOS, дождаться статуса регистрации.
7. Нажать «Отправить тестовое уведомление», заблокировать iPhone и проверить последний ответ Apple (`200` означает только принятие APNs). Проверь iOS Settings → Notifications → Spyder, Focus и Silent Mode.
8. На iPhone A отправить реальное сообщение на B; проверить внешний push и выбранный звук. Не считать тест завершённым без двух устройств.

В Cloudflare должны оставаться `APNS_PRIVATE_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID=com.spyder.wallet`, `APNS_ENVIRONMENT=production`. Приватные ключи не попадали в ZIP.

Если Cloudflare deployment падает с `Headers.set invalid header value`, исправить переносы в **GitHub** `CLOUDFLARE_API_TOKEN` — это отдельная ошибка Wrangler, не связанная с APNs.

## Ограничения релиза

- Доставка push между настоящими iPhone не проверена в локальной среде.
- Этот патч не заменяет независимый аудит E2EE.
- Полный Xcode build и Cloudflare Wrangler deploy требуют macOS GitHub Actions/реальный Cloudflare.
- Ранее существовавшие копии исторических v1-сообщений автоматически не удаляются.
