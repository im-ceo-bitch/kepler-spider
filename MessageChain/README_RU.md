# Spyder MessageChain — Block 1 / research devnet v0.1

**Это первый экспериментальный блок, а не защищённый готовый мессенджер.** Никаких изменений SwiftUI, WalletVault, Keychain, Apple-signing или текущих Console Chat endpoints.

## Что реализовано
- Message Block: Ed25519-подпись и SHA-256 хеш всей записи, две независимые связанные последовательности в одном диалоге.
- Демо E2E-полезная нагрузка: X25519 key agreement, HKDF-SHA256, AES-256-GCM с аутентификацией заголовка. Уникальный эфемерный отправитель на каждое сообщение.
- Проверка подписи на relay без возможности прочитать plaintext.
- Cloudflare Workers + SQLite-backed Durable Objects для HTTP доставки и хранения ciphertext, WebSocket hibernation для уведомления о новом блоке.
- Одна комната на диалог, контроль последовательности, hash предыдущего блока, повторов, перекрёстных ссылок, лимит 1 000 записей на экспериментальный диалог.
- Только закрытый тестовый доступ через `DEVNET_OPERATOR_TOKEN` (НЕ включать этот секрет в приложение или публичный сайт).

## Проверка локально

```bash
cd MessageChain/relay
npm test
npm run check
```

Не требуется `npm install` для тестов; Node.js 22+.

## Cloudflare DEVNET deployment — только после проверки протокола

```bash
cd MessageChain/relay
npm install
npx wrangler secret put DEVNET_OPERATOR_TOKEN
npx wrangler deploy
```

Токен предназначен для тестового CLI или доверенного оператора. **НЕЛЬЗЯ вставлять DEVNET_OPERATOR_TOKEN в iOS:** его извлекут и получат доступ ко всему devnet. В production нужна криптографическая авторизация отдельными ключами участника, без общего токена.

Дальше можно тестировать вручную: `POST /v1/conversations/<64hex>/init` с JSON `{"participants":["<base64 spki Ed25519 A>","<base64 spki Ed25519 B>"]}`, затем `POST /v1/conversations/<64hex>/envelopes`, `GET .../envelopes?after=0` и `wss://.../v1/conversations/<64hex>/socket`.
Все запросы кроме `/health` требуют заголовка `x-spyder-devnet-token`.

## Чего пока нет — критично для честной оценки
- **Нет global consensus** и независимых валидаторов: у нас криптографически связанная переписка, НЕ завершённый децентрализованный блокчейн.
- Нет Double Ratchet/MLS, **нет forward secrecy** в случае компрометации постоянного ключа получателя. Эфемерный ключ отправителя не исправляет эту проблему.
- Нет seed-based identity, безопасного восстановления после импорта кошелька, мультидевайс, APNs, публичного username и Stealth-invite.
- Нет полноценной защиты от отказа в доставке, fork/equivocation, metadata analysis, клиентского anti-rollback и внешнего аудита.
- Для коммерческого релиза потребуется криптографическая независимая проверка и антиспам.
- Существующий Console Chat **НЕ** становится E2E от установки этого ZIP; пользователям нельзя показывать отметку «сквозное шифрование».

## Последовательность следующих блоков
1. Crypto ratchet (независимые ключи сообщений), подписанный invite, identity-bound session, key transparency, secure local state.
2. Seed-to-chat identity через domain-separated derivation, без передачи сид-фразы или кошельковых приватных ключей, после аудита восстановления.
3. Безопасная client auth, offline queues, APNs without plaintext, редактирование SwiftUI Chats и миграция от Console plaintext без потери истории.
4. Независимые операторы/узлы и consensus/fork reconciliation для настоящей децентрализации MessageChain.

## Почему отдельная папка
В предоставленном `kepler-spider-main 3.zip` лежат две существующие реализации Chats, в одной из которых plaintext отправляется на сервер. Этот эксперимент **намеренно изолирован** от действующего приложения. Нельзя включать новый транспорт до реализации ratchet, авторизации и проверенного iOS-клиента.
