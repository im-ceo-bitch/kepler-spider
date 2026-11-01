# Spyder Wallet — Portfolio & Asset Experience (01.11.2026)

## База
Изменения выполнены поверх `kepler-spider-main 3.zip`, который уже содержит Block 1–4 и Motion Kit. ZIP — **точечное обновление** с путями относительно корня репозитория. Не содержит `.github/workflows`, не изменяет сервисы Chat, сервер, Motion Kit, генерацию сид-фраз и криптографические ключи.

## Что изменено

- `WalletHomeView.swift`: закреплённая под статус-баром панель; новый портфель с реальными данными и отметкой неполной оценки; компактные действия; единый интерактивный каталог BTC/ETH/SOL/USDT/USDC; история без технических заглушек; Spider Chain Devnet в закрытом по умолчанию раскрывающемся блоке, только когда настроен.
- `WalletProductViews.swift`: переработанные карточки нативных монет; отдельная страница ERC-20 токенов с allowlisted контрактом и адресом Ethereum; история операций, если её возвращает источник; кнопки получения и копирования.
- `WalletTransferView.swift` и `WalletRootView.swift`: общий Receive теперь открывает Ethereum Mainnet по умолчанию (вместо SPD Devnet), тестовая сеть перенесена после основных сетей в выборе.
- Добавлены RU/EN-строки и статические UI-регрессионные тесты.

## Состояние криптовалютных функций

- Показ BTC/ETH/SOL/ERC-20 зависит от публичных RPC. Нет гарантии полной истории или доступности каждого провайдера. Пустое значение не следует считать нулевым балансом.
- Подпись и публикация Mainnet-транзакций **намеренно отключены** в прежнем `WalletSendFlowView`. Обновление не делает кошелёк production-ready для перевода средств.
- Solana history не показывает выдуманный баланс-дельта.
- Не включены Swap, покупки, исторические графики, подтверждённая комплексная индексация и подтверждённая полноценная система отправки BTC/ETH/SOL.
- Тестовый SPD не стал Mainnet.

## Проверка

- `python3 ci/verify_repo.py`
- `python3 -m unittest discover -s ci/tests -q`
- `python3 -m unittest discover -s tests -q`
- `swiftc -frontend -parse $(find Console -name '*.swift' -type f)`
- `plutil -lint Console/Resources/{ru,en}.lproj/Localizable.strings`
- Серверные и сетевые Node-тесты без изменений.

**Не выполнено:** `xcodebuild` на macOS, Xcode iOS typecheck и проверка Safe Area/динамического размера шрифта в симуляторе или на iPhone. Перед TestFlight необходимо сделать build-only CI gate и визуальную QA на устройствах.

## Установка

1. Убедитесь, что ваш `main` соответствует репозиторию `kepler-spider-main 3.zip` (если после этого были изменения в SwiftUI, сначала сопоставьте пути).
2. Загрузите `console-update-spyder-wallet-portfolio-20261101.zip` в корень репозитория. Распаковщик должен сохранить пути файлов относительно корня, без внешней папки.
3. После распаковки проверьте изменения `Console/Features/Wallet/*`, `Console/WalletRootView.swift` и ресурсах локализации, затем запустите build-only на GitHub Actions до TestFlight.
