# Spyder Wallet v0.5 — Live Chat Devnet + Spider Protocol address

**Накопительное обновление:** поверх Console→Spyder Wallet v0.1, v0.2, v0.3, v0.4 или v0.4.1. Все файлы предыдущих версий и исправление WalletCoreSwiftProtobuf включены. ZIP распознаёт старый бот: `console-update*.zip`.

## Установка приложения

1. Загрузи один ZIP `console-update-spyder-wallet-livechat-v05.zip` в корень существующего GitHub-репозитория Wallet.
2. Дождись `Console — Auto Unpack Update`. Патч заменяет `server/`, но НЕ изменяет `.github/workflows` и Apple-подпись.
3. Запусти действующий Intel TestFlight workflow. `com.console.beta`, Xcode scheme `Console` сохранены.

## Включение чата на двух iPhone

1. Запусти старый workflow `Console — Deploy Realtime Server` вручную; если его нет, см. `server/README.md` и `SPYDER_CHAT_DEPLOY.yml.txt`.
2. Deployment требует Cloudflare API token/account secrets. Worker будет называться `spyder-chat-devnet` (новый, не старый Console).
3. Вставь HTTPS Worker URL в Chats на обоих устройствах. Создай **два разных** профиля.
4. Пригласи друг друга кодом, на втором устройстве прими запрос. Теперь текстовые сообщения передаются через backend и сохраняются, открытый чат обновляется примерно раз в 3 секунды.

Важно: СООБЩЕНИЯ НЕ ИМЕЮТ E2EE и читаются оператором Cloudflare Worker; это тестовое приложение, а не защищённый production-мессенджер. Нет APNs, приложению нужно быть открытым для опроса новых сообщений. Фраза кошелька никогда не используется для регистрации в чате.

## Spider Chain

В Wallet появился адрес `spider1…` из BIP-39 фразы (экспериментальный SLIP-0010 путь, см. `contracts/SPIDER_CHAIN_RPC_HANDOFF.md`). Testnet баланс и переводы SPD пока **не подключены**: в предоставленном репозитории блокчейна нет ни REST/RPC узла, ни P2P, ни постоянного ledger. Никаких поддельных подтверждений.

## Проверки

- Проверка синтаксиса Swift не равна Xcode компиляции.
- `server/npm run check`: синтаксис JS + тесты реальной логики Worker на моковом persistent DO.
- `server/test/spider_reference.py`: независимый Python reference derivation; нужен Python cryptography локально, на GitHub workflow не требуется.
- Проверены структура, ресурсы и наложение ZIP на v0.4.1. Финальная Xcode-компиляция и реальные тесты на двух телефонах требуют запуска GitHub.
- До аудита НЕ ИМПОРТИРОВАТЬ сид-фразы с реальными деньгами.
