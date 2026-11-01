# Spyder Chat v2 + MessageChain v1 — безопасное развёртывание на существующий Worker

**Цель:** один Cloudflare Worker `kepler-spider`, адрес `https://kepler-spider.helloiumrah.workers.dev`, два независимых Durable Objects. Изменение имени Worker создаст отдельный ресурс и не перенесёт существующую историю.

## Что именно меняется

- Старый MessageChain остаётся с прежними `/health`, `/v1/conversations/<64hex>/{init,envelopes,socket}`, Durable Object `MESSAGE_ROOMS` → `SpyderMessageRoom`. Операторская авторизация `DEVNET_OPERATOR_TOKEN` не отключается.
- Chat v2 обслуживает `/v1/register`, `/v1/me`, `/v1/invites`, `/v1/users/search`, `/v2/...`. Durable Object `CHAT_HUB` → `ChatHub`, независимое новое SQLite-пространство.
- Специальный адрес проверки Chat v2: **`/chat/health`**. **Старый `/health` намеренно продолжит возвращать MessageChain v1**, чтобы ничего не сломать.
- iOS теперь проверяет именно `/chat/health`; загрузка старого Chat Production ZIP не нужна — этот архив включает изменения Chat Production вместе с объединением Worker.
- В `server/wrangler.jsonc` присутствуют обе привязки и две миграции: уже существующая `v1` для `SpyderMessageRoom` и новая `v2-add-chat-hub` для `ChatHub`. Нет операций `deleted_classes` или `renamed_classes`.

## Перед загрузкой ZIP

1. Убедиться, что Cloudflare Worker называется **`kepler-spider`** именно в том аккаунте, где GitHub Secret `CLOUDFLARE_ACCOUNT_ID`.
2. Убедиться, что там сохранена привязка `MESSAGE_ROOMS` → `SpyderMessageRoom`. Если фактическая история миграций существующего Worker отличается от ожидаемой `v1`, **не выполнять deploy** — сначала сверить с Cloudflare. Скриншот активной привязки это подтвердил, но tag миграции из скриншота не виден.
3. Проверить созданные в этом Worker: `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID=com.spyder.wallet`, `APNS_ENVIRONMENT=production`. Не публиковать приватные значения.
4. Проверить GitHub Actions Secrets: `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`, `SPYDER_CHAT_SERVER_URL=https://kepler-spider.helloiumrah.workers.dev`.
5. Для старых операторских MessageChain-запросов нужен отдельный `DEVNET_OPERATOR_TOKEN` (не сохранять его в iOS и не пересылать). Если токен отсутствует, старые операционные вызовы останутся запрещены HTTP 403; `/health` продолжит работать.

## Порядок выкладки

1. **Сохранить резервные копии** существующих настроек/исходников Worker и, если там есть данные, настроить Cloudflare Durable Objects SQLite point-in-time recovery / backup процедуру до вмешательства. Не выполнять сброс состояния.
2. Загрузить **только один** `console-update*.zip` в корень репозитория. `Console — Auto Unpack Update` должен завершиться зелёным. Из-за ограничения распаковщика изменения файлов `.github/workflows/` этим архивом не передаются.
3. Проверить в main `server/wrangler.jsonc`: name=`kepler-spider`, `MESSAGE_ROOMS` и `CHAT_HUB` одновременно. `server/src/index.mjs` должен импортировать старый MessageChain и новый ChatHub.
4. Проверить локальные/CI-тесты `cd server && npm run check`, а также `node --test MessageChain/tests/*.test.mjs` из корня.
5. **Запустить вручную** `Console — Deploy Realtime Server` в GitHub Actions только после проверки. Существующий workflow может автоматически запускаться при ручных изменениях `server/**` в main. До успешного деплоя не выпускать iOS TestFlight. Если Cloudflare сообщает о конфликте миграций — остановиться и собрать сведения; не удалять классы/namespace.
6. После развёртывания открыть:
   - `https://kepler-spider.helloiumrah.workers.dev/health` — ожидается `{"status":"ok","name":"spyder-messagechain-devnet","version":1,"e2ee_audited":false}`.
   - `https://kepler-spider.helloiumrah.workers.dev/chat/health` — ожидается `{"status":"ok","service":"spyder-chat-devnet","version":2,"e2ee":true}`.
   - Повторно проверить привязки `MESSAGE_ROOMS` и `CHAT_HUB` в Cloudflare.
7. Затем собрать TestFlight с `SPYDER_CHAT_SERVER_URL` (без `/health`) и entitlement `aps-environment=production`; на двух физических iPhone проверить создание @username, поиск, приглашение, принятие, E2EE сообщение, ответ, APNs на заблокированном экране.

## Чего этот PATCH не делает

- Не создаёт второй Worker, не переносит и не стирает старые MessageChain-конверсации, не превращает MessageChain в Chat v2 и не переносит их протоколы друг в друга.
- Не доказывает работоспособность APNs без реального устройства и Apple/Cloudflare deployment.
- Не реализует несколько независимых профилей на одном устройстве, мультидевайс, Double Ratchet или независимый криптоаудит.
- Не может проверить фактический живой Worker migration tag из ZIP. `wrangler deploy` и Xcode build в этой среде не выполнены.

## При ошибке

Не удалять `MESSAGE_ROOMS`, не переименовывать `SpyderMessageRoom`, не менять account/Worker name, не использовать `wrangler delete` и не сбрасывать DO storage. Возвратить предыдущую версию кода Worker через Cloudflare Deployments и проверить `/health`. Для ошибок миграции нужна диагностика до попытки повторного деплоя.
