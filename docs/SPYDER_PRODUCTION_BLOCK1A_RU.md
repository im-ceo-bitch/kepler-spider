# Spyder Wallet — Production foundation / 1A

База: архив `kepler-spider-main.zip`, commit `402ad44162214430e752667f896d9668f1fd8cbe`.
Это первый ограниченный security-патч, не завершение Wallet Core и не допуск к реальным средствам.

## Изменения
- `WalletUnlockGate` — одноразовый идентификатор попытки системной аутентификации. Блокировка инвалидирует LAContext и отклоняет запоздалый callback. Повторные нажатия не создают параллельные запросы.
- `WalletAddressValidator` — EIP-55 на существующем Keccak-256 для mixed-case адресов, отказ для нулевого ETH-адреса. Однорегистровые адреса остаются допустимыми, без гарантии checksum. Проверка выполняется также перед извлечением ключей при EVM-подписании. Старые записи адресной книги читаются по прежним правилам, но не обходят проверку новых операций. Для дубликатов Solana используется точное сравнение регистра.
- При изменении активного аккаунта отменяется авторизация USDT в корневом приложении.
- `WalletEVMBroadcastStaging` — повторный атомарный claim после await chainId; устранение reentrancy гонки в **тестовом** транспорте. Production-флаг не изменён.
- Seed, derivation paths, Keychain identifiers, исходная структура UI, production RPC и workflows не изменены.

## Аудит текущей базы
- Реализованы BIP39/Keychain, независимые кошельки, деривация ETH/SOL/BTC, локальная подпись EIP-1559, проверка подписи и durable journal для USDT в чате.
- Ручная отправка ETH/USDC и произвольных адресов в WalletSendFlowView остаётся preview. SOL/BTC не имеют подтверждённого полного send pipeline в приложении.
- Spider Devnet: отдельный клиент, проверка сертификатов и тестовая отправка SPD; live devnet не проверялся.
- Чат: TOFU single-device E2EE по исходному коду, не audited double ratchet. Наличие кода не подтверждает доступность backend.
- Нет найденной реализации полноценного DEX swap, cross-chain bridge, WalletConnect, NFT portfolio в Console.
- Дополнительный риск для следующего этапа: создание seed и запись account index не атомарны; iCloud recovery и Keychain миграции требуют проверки на устройствах. Не менять схему хранилища без migration tests.

## Проверки
- Исходный набор `pytest -q ci/tests`: 177 passed, 2 failed, 11 subtests passed. Два исходных сбоя: `test_spyder_terminal_v2_integration.py` ожидает старую зависимость TerminalKit и старый chat wrapper. Не отключены и не исправлены в этом патче.
- После правок: 14 passed в `test_wallet_security_foundation.py`, `test_wallet_evm_stage5.py`, `test_wallet_address_book_next.py`, `test_wallet_evm_stage2.py`. Swift 5/6 language mode, checksum/lock vectors, deterministic concurrent broadcast regression.
- Swift frontend parse изменённых production-файлов: успешно. Это синтаксическая проверка, не iOS typecheck.
- Полный повторный CI, backend, Xcode, Simulator, физический iPhone, Face ID, Keychain, live RPC и внешний security audit не подтверждены.

## Установка
Загрузить один ZIP `console-update-production-block1a.zip` в корень репозитория. Существующий console-auto-unpack.yml обнаруживает `console-update*.zip`, накладывает файлы и удаляет архив. Workflow не заменяется. После распаковки выполнить существующую сборку и проверить отчёт CI. Не использовать патч как разрешение на production mainnet.
