# Spyder Wallet — Network Expansion & Route Preview (3A)

## Установка
Накопительный ZIP включает все 37 файлов Block 2A и новые/изменённые файлы этого этапа. Распаковывать в корень репозитория штатным console-auto-unpack. Workflow, project.yml, bundle ID, seed и derivation paths не изменены. Новые Swift-файлы входят в Console через действующую конфигурацию XcodeGen.

## Что работает в коде
- Новый раздел «Сети и маршруты» на главном экране. Вход только после существующей аутентифицированной деривации адреса Ethereum для выбранного аккаунта. При смене аккаунта или отзыве верификации экран закрывается.
- Нативные EVM-балансы Ethereum, Arbitrum One, OP Mainnet, Base, BNB Smart Chain и Polygon PoS. Запрос chain ID перед чтением баланса для каждого провайдера, резервный RPC, точное представление uint256 в десятичных строках, отказ при неверном ответе. Только read-only; проверка Chain ID не является криптографическим доказательством баланса.
- Отдельная оценка стоимости нативных EVM-активов на основе CoinGecko, с временными метками котировок и балансов. Просроченные/отсутствующие данные не включаются; неполная оценка помечается. Нулевой проверенный баланс не требует рыночной цены. Оценка в Decimal приблизительная, базовые единицы сохранены точно. Не суммировать этот показатель с общим балансом главной страницы: Ethereum пересекается. ERC-20, SOL, BTC и SPD не входят в новую EVM-сводку.
- Предварительный Swap/Bridge через GET https://li.quest/v1/quote: нативные активы шести EVM-сетей и USDC Ethereum. Провайдер может не иметь маршрута или потребовать ключ. Проверка идентичности сетей, токенов, decimals, владельца, исходной суммы, slippage, минимального выхода и срока (45 секунд). Calldata, approvals и transactionRequest не используются. Комиссии и реальное исполнение не проверены. Перед запросом пользователь видит предупреждение об отправке публичного адреса и суммы LI.FI.
- WalletWeb3Policy — изолированная deny-by-default политика для будущего WalletKit: проверяет аккаунт, CAIP-2 сеть и допустимые read-only методы. Никакого активного WalletConnect-соединения, паринга, подписи, передачи аккаунта dApp или сохранения сессий в этой версии нет.
- Сетевой транспорт не следует HTTP-redirect, ограничивает срок запроса и размер принимаемого ответа. Публичные endpoint'ы могут ограничивать запросы или меняться.

## Что НЕ завершено / release gates
1. Полная отправка/получение новых EVM-сетей, SPL/Bitcoin, токены/NFT discovery, единый агрегированный портфель всех сетей. Не использовать новый экран как подтверждение готовности отправки.
2. Swap/Bridge: реальный запрос к LI.FI на устройстве, проверка маршрутов, calldata, разрешённых контрактов и approvals, независимая симуляция, явное согласие, исполнение на testnet, отслеживание bridge до назначения, recovery и отдельный аудит. Не включать mainnet execution раньше этих проверок.
3. WalletConnect: подключение официального Reown WalletKit через SPM, действующий Project ID, конфигурация URL scheme и redirect metadata, обработка pairing/session proposals, scoped grants, expiry/revocation, проверка dApp, явное подтверждение каждого опасного запроса, testnet E2E. См. https://docs.walletconnect.com/wallets/ios/installation и https://github.com/reown-com/reown-swift . Политика в текущем ZIP не подключена к SDK.
4. Сборка Xcode, тесты на устройстве, проверка RPC и LI.FI по сети не выполнялись в Linux. Не выпускать как production mainnet-релиз без этих проверок и независимого аудита безопасности.

## Воспроизводимые проверки
```
python -m pytest -q ci/tests/test_wallet_network_expansion.py ci/tests/test_wallet_portfolio_ui.py ci/tests/test_wallet_market_engine.py ci/tests/test_wallet_real_receive.py ci/tests/test_wallet_evm_stage1.py ci/tests/test_wallet_security_foundation.py ci/tests/test_wallet_live_market.py
swiftc -typecheck Console/WalletCore/WalletEVMPreflight.swift Console/WalletCore/WalletNetworkExpansion.swift Console/WalletCore/WalletRoutePreview.swift
swiftc -frontend -parse Console/Features/Wallet/WalletNetworkPortfolioView.swift Console/Features/Wallet/WalletHomeView.swift
```
Результат: 24 Python/Swift теста прошли. Новый драйвер проверяет точность uint256, fallback RPC, неверную сеть, подмену адреса/суммы/актива, просроченные котировки, stale valuation, scoped Web3 policy и запрет подписания. Это локальные сценарии с mock-ответами, а не проверка live mainnet. Весь CI-набор повторно не запускался на данном этапе. Синтаксическая проверка не заменяет Xcode typecheck SwiftUI.
