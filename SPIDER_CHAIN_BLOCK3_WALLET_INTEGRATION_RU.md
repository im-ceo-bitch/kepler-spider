# Spyder Wallet / Spider Chain Block 3 — интеграция Devnet, 31.10.2026

## Что установлено

- Исходные iOS-контракты перенесены из предоставленного `kepler-blockchain-main 4.zip` без выдуманных RPC: `SpiderDevnetSigner.swift`, `SpiderCertifiedWalletClient.swift`, `SpiderWalletDevnetBridge.swift`.
- Блокчейн-идентичность сохраняется: Wallet уже содержит версионированный тестовый derivation BIP-39/SLIP-0010 `m/44'/9999'/0'/0'`. Новый signer использует тот же Ed25519 ключ, подписывая локально после подтверждения Face ID. Ни ключ, ни сид не передаются в сеть. Это **не утверждённый общесетевой mainnet-стандарт**.
- Экран профиля -> **Spider Chain · Devnet**: HTTPS URL шлюза, настоящий 64-hex genesis хеш, bearer токен из защищённого окружения (Keychain, не исходники).
- Spider Chain на главном экране: test SPD адрес, подтверждённая высота, баланс, статус подключения, очередь исходящей транзакции, ссылка на настройки через профиль.
- Отправка: строго правильный `spider1…` Bech32m адрес, сумма в целых атомарных единицах (9 знаков), проверка состояния/баланса/nonce/комиссии, локальная Ed25519 подпись, POST в шлюз, сохранение Pending до сетевого ответа, отдельная проверка реальной финализации.
- Получение: отдельная сеть Spider Chain и QR-код. ETH/BTC/SOL и чаты оставлены без изменений.
- Сертифицированная история тестовых SPD из `/v1/accounts/{address}/transactions`, только verified BFT evidence; не показывать очередь как окончательный перевод.
- Pending nonce резервируется до HTTPS POST, сохраняется между перезапусками, блокирует конкурирующие отправки; может освободиться при финализации либо если сеть удостоверила истечение срока подписи и неизменность nonce.
- Тесты iOS в `Tests/SpiderDevnetIntegrationTests.swift` (XCTest) и target `ConsoleTests` в `project.yml`.

## ЧТО НЕЛЬЗЯ СЧИТАТЬ ГОТОВЫМ

1. Это **research Devnet**, а не mainnet/платёжный сервис. Нельзя принимать реальные SPD, USDT, BTC или другие средства через адрес Spider Devnet.
2. ZIP не содержит работающего публичного шлюза, его DNS, сертификатов, genesis, выделенных токенов или работающего четырёхвалидаторного кластера. Все эти значения нужно развернуть **вне iOS репозитория**.
3. Требуется реальная проверка iPhone → HTTPS gateway → queue → ingress → gossip → BFT → certified ledger → iPhone. Сборка приложения не доказывает этот сценарий. iOS доверяет TLS и выбранному genesis шлюза; не выполняет полную верификацию каждого доказательства консенсуса на телефоне.
4. При невозможности проверить finality транзакция остаётся Pending. HTTP 202 нельзя обозначать как success. Механизм однозначно освобождает nonce только при проверке ledger.
5. iOS разработка здесь проверена средствами анализа исходников; **фактический Xcode build/TestFlight нужно выполнить на macOS**. Не считать этот ZIP подтверждённым двоичным релизом.

## Установка ZIP (GitHub bot)

Загрузить **один** файл `console-update-block3-wallet-devnet.zip` **в корень** репозитория `kepler-spider-main` через GitHub UI. Текущий workflow `.github/workflows/console-auto-unpack.yml` ищет префикс `console-update*.zip`, распакует overlay без создания второго `Console/` каталога. ZIP не меняет секреты GitHub/Apple, signing или существующие workflows.

После зелёного Auto Unpack запустить TestFlight workflow с `build_only=true` (обязательная сборка Debug + Release), проверить приложение в iOS Simulator/на iPhone. На Mac тесты можно запустить командой:

```sh
xcodegen generate
xcodebuild -project Console.xcodeproj -scheme Console -showdestinations
xcodebuild test -project Console.xcodeproj -scheme Console \
  -destination 'platform=iOS Simulator,name=ИМЯ_ДОСТУПНОГО_СИМУЛЯТОРА' CODE_SIGNING_ALLOWED=NO
```

Сначала убедиться, что XcodeGen создал `ConsoleTests`.

## Подключение реального Devnet

1. На выделенных серверах развернуть Spider Chain Block 3 (4 валидатора с одним genesis, отдельно защищённые Rust loopback RPC, mTLS между узлами). Запустить `gateway/spider_wallet_gateway.py`, HTTPS Caddy reverse proxy. Данные не копировать в репозиторий.
2. На приватном сервере получить `chain_id=spider-devnet-1`, `genesis_hash` (64 hex) и `network=SPIDER_CERTIFIED_DEVNET_RESEARCH` через авторизованный `/v1/status`.
3. Профиль -> Spider Chain · Devnet: ввести HTTPS origin, pinned genesis hash и настоящий 64-hex bearer. Не публиковать его в исходниках, переписке, скриншотах или логах. Сервер должен предоставлять отдельные отзываемые токены для устройств при расширении доступа.
4. В Wallet нажать «Открыть SPD-адрес» и пройти Face ID. Выделить **тестовые SPD** этому адресу в соответствующем genesis, либо финансировать его тестовым переводом из уже существующего funded адреса.
5. Проверить статус и баланс, затем отправить малую тестовую сумму на другой созданный `spider1…` адрес. Убедиться, что сначала `pending`, затем `finalized` с блоком и hash и история после обновления отражает операцию.
6. Проверить перезапуск/блокировку приложения во время Pending, лидера BFT, падение/возврат валидатора и отсутствие двойного расходования nonce.

## Гейты, выполненные при подготовке

- 31 Swift файл приложения + XCTest файл: синтаксический parse через swiftc — OK (не typecheck под iOS SDK).
- `python ci/verify_repo.py` — OK.
- `python -m unittest discover -s ci/tests` — 7 тестов OK.
- Chain gateway Python tests — 11 тестов OK.
- Реальный `xcodebuild`, `xcodegen`, simulator и iPhone E2E в данной среде **недоступны**.
