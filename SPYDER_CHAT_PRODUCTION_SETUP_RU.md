> **ВАЖНО: инструкция ниже относится к прежнему отдельному Worker. Для текущего существующего `kepler-spider` используйте `SPYDER_UNIFIED_CHAT_DEPLOY_RU.md`!** Не разворачивайте отдельный `spyder-chat-devnet`, не ожидайте Chat v2 на `/health`; объединённый сервер использует `/chat/health`.

# Spyder Chat Production — настройка и реальные проверки (01.11.2026)

## Что изменено в этом PATCH
- Cloudflare Chat v2: авторизованная регистрация и отзыв APNs-токена (`/v2/push/register`, `/v2/push/unregister`), `/v2/push/status`.
- Уведомление после нового запроса и нового encrypted envelope; повторная отправка того же client_id не создаёт повторный push.
- Worker подписывает APNs JWT ключом ES256 (ключ хранится только в Cloudflare secrets). В push уходит общий текст «Новое зашифрованное сообщение», **не содержимое чата**.
- iOS: разрешение на push пользователь включает сам в Сеть → Spyder ID → «Уведомления о сообщениях»; токен передаётся серверу только по HTTPS после входа в чат.
- Тап по push открывает вкладку «Сеть», но перед просмотром чата пользователь обязан разблокировать кошелёк.
- При создании ID можно осознанно включить видимость @username в поиске (по умолчанию в новом интерфейсе переключатель включён, его можно отключить). Сервер принимает `discoverable` только при регистрации; старые клиенты сохраняют прежнюю настройку.
- Старые chat ID / кошельки / E2EE ключи / DO migration не изменены.

## Что обязательно сделать владельцу Cloudflare и Apple до настоящего запуска

1. В Apple Developer (Certificates, Identifiers & Profiles → Identifiers → `com.spyder.wallet`) включить **Push Notifications**. Создать APNs Auth Key (.p8) в разделе Keys. **Это отдельный APNs-ключ**, не API-ключ App Store Connect. Записать APNs Key ID и Apple Team ID.
2. В Cloudflare Dashboard → Workers & Pages → Worker `spyder-chat-devnet` → Settings → Variables and Secrets добавить секреты:
   - `APNS_TEAM_ID` — Apple Developer Team ID (обычно 10 символов)
   - `APNS_KEY_ID` — именно APNs Auth Key ID (обычно 10 символов)
   - `APNS_PRIVATE_KEY` — полный текст `-----BEGIN PRIVATE KEY----- ...` `.p8` (без публикации в репозитории)
   - `APNS_BUNDLE_ID` — `com.spyder.wallet` (должен совпадать с итоговым идентификатором TestFlight-приложения)
   - `APNS_ENVIRONMENT` — `production` (TestFlight использует production APNs)
3. В GitHub Actions Secrets проверить `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` и `SPYDER_CHAT_SERVER_URL`. Последний — **публичный HTTPS-адрес именно этого Worker**, без `/health` и без пробелов, например `https://<your-worker>.<your-subdomain>.workers.dev`. Не придумывать адрес и не подставлять другой аккаунт.
4. Залить update ZIP в корень репозитория. Дождаться успешной распаковки и появления файлов в main.
5. В GitHub Actions запустить **Console — Deploy Realtime Server** вручную (`workflow_dispatch`). Commit от распаковщика может не запустить второй workflow автоматически. Worker должен остаться в **том же Cloudflare account и с тем же именем** и Durable Object `CHAT_HUB` — иначе прежние профили не будут видны.
6. Открыть `<SPYDER_CHAT_SERVER_URL>/health`: ожидать `{"status":"ok","service":"spyder-chat-devnet","version":2,"e2ee":true}`.
7. В GitHub Actions запустить обычный **Spyder Wallet - TestFlight Cloud Signing**. Для автоматической подписи Apple должен быть доступен Push Notifications capability и production entitlement. В `.xcarchive`/подписанном приложении проверить `aps-environment=production`.
8. На **двух настоящих iPhone** с двумя отдельными Spyder Chat ID: зарегистрировать уникальные @username, включить поиск, найти другого по @username, отправить запрос, принять его на втором устройстве, сверить отпечатки ключей вне чата, отправить и прочитать зашифрованные сообщения в обе стороны. В Spyder ID каждого телефона включить уведомления, дать разрешение iOS, заблокировать экран второго телефона и отправить ему новое сообщение. Проверить появление системного APNs-уведомления и реальную загрузку переписки после разблокировки. Проверить отказ в разрешении, offline, повторные client_id, блокировку контакта, повторный вход.

## Ограничения и статус
- **Невозможно считать real-device delivery проверенной** без доступа к вашему Cloudflare и Apple Developer/APNs и без двух iPhone. Текущий серверный код проверен локальными Node-тестами; Swift проверен парсером, не Xcode build.
- Нет готовой мультиустройственной синхронизации, нескольких независимых Spyder ID, Double Ratchet, push с расшифрованным предпросмотром и массовой push-очереди. Эта версия — **pilot / pre-production**, не прошла независимый криптографический аудит.
- Сервер знает метаданные отправителя, получателя, время и ciphertext lengths. APNs получает тип события и generic alert, но **не текст** сообщений.
- APNs может задержать или не показать уведомление из-за сети, разрешений и политик iOS. Ответ сервера `sent` означает сохранение зашифрованного сообщения, не доставку на экран получателя.
- Отказ push не блокирует отправку сообщения. При отсутствии конфигурации APNs регистрация вернёт ошибку `push_not_configured`.
- В режиме Debug с development APNs нужен development entitlement и `APNS_ENVIRONMENT=development` в отдельной среде Cloudflare; не смешивайте dev-токены с production токенами TestFlight.
