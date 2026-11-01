# Spyder Wallet — Block 7, Stage 1: ETH / ERC-20 Read-only Preflight

## База и способ установки

Установка поверх `kepler-spider-main 3.zip` + `console-update-spyder-wallet-terminal-unified-rechecked-20261101.zip` (либо поверх `main`, уже соответствующего этому состоянию). ZIP содержит только изменённые файлы, пути от корня репозитория, без внешней папки и без `.github/workflows`.

**Установка ZIP не равнозначна подтверждённой TestFlight-сборке.** Перед TestFlight запустите build-only CI на macOS/Xcode 26.6. Интеграционные UI-тесты на устройстве и независимый аудит безопасности ещё не выполнены.

## Функции

- В Send Flow можно выбрать ETH, USDT и USDC в сети Ethereum Mainnet.
- Только для ETH/ERC-20: запросы `eth_chainId`, pending nonce, pending ETH balance, baseFee EIP-1559, priority fee, `eth_estimateGas` и при необходимости `eth_call.balanceOf` на проверенный контракт токена.
- Для ETH и ERC-20 вычисляется максимальная комиссия в ETH и проверяется достаточность ETH на неё. Для токенов проверяется отдельный token balance; публичные RPC возвращают приблизительные оценки и могут ошибаться.
- Контракты USDT и USDC строго закреплены в коде, все суммы кодируются из десятичных строк без Double. Точность 18 (ETH) и 6 (USDT/USDC).
- API адресов не получают приватные ключи или seed-фразу. Запросы выполняются к публичным Ethereum RPC через HTTPS и ограничены по времени/размеру.
- Поддержаны ошибки: чужая сеть, неверный ответ RPC, невалидная сумма, недостаточный баланс, высокая комиссия. Проверка адреса Ethereum пока **только синтаксическая**, без EIP-55 checksum.
- BTC и SOL оставлены в прежнем просмотре реквизитов (без новой оценки gas).

## КРИТИЧЕСКОЕ ОГРАНИЧЕНИЕ

Это **не финальный Real Transaction Engine**. Никакой подписи/отправки транзакций и вызовов `eth_sendRawTransaction` здесь **нет**. Кнопка отправки остаётся заблокированной. Это намеренная защита от ложного ощущения возможности отправить средства.

Прежде чем безопасно включить реальные средства, нужны: проверенная EIP-1559 сериализация и подпись в WalletCore на устройстве, проверка подписанного payload (chainId 1, адрес, contract, nonce, value, data), EIP-55 checksum validation, интеграционные тесты на тестовой сети, nonce management и replacement transactions, подтверждение/отмена, гарантированная работа с недостаточными комиссиями и reorg, независимый аудит.

## Что не изменялось

`ConsoleApp.swift`, `WalletRootView.swift`, чаты, сервер Chat Unified, Keychain и WalletVault, SpyderTerminalKit, проект/зависимости и GitHub workflows.

## Критерии проверки

Первая проверка: тесты на полнофункциональной рабочей копии. Вторая: самостоятельное извлечение финального ZIP на чистую копию заданной базы и повторный запуск тех же тестов + сверка файлов.

Используйте `python3 ci/verify_repo.py`, `python3 -m unittest discover -s ci/tests -v`, `swift test --package-path Packages/SpyderTerminalKit`, `npm test` в `server` и `relay`; затем полноценный Xcode build-only.
