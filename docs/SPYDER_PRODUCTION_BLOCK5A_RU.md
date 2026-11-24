# Block 5A — Sepolia execution, public inventory and recipient safety

Накопительное обновление поверх 4A. Не является заявлением о готовности 85% или разрешением на эксплуатацию реальных средств.

## Что добавлено
- Отдельный экран Networks & Routes → Sepolia testnet: проверка суммы, два RPC (PublicNode и 1RPC), pending nonce, gas, максимальная комиссия, симуляция, повторная проверка перед подписью и отправкой. Только native test ETH / EIP-1559, chain ID 11155111. Ключ берётся из существующего Keychain по системной авторизации. Подписанное RLP сопоставляется с намерением, проверяется локальный Keccak и восстановленный адрес подписанта. Публикация только однажды, в один RPC, с сохранением публичной записи до отправки.
- При неопределённом результате повтор блокируется; статус проверяется по двум RPC с совпадающим receipt и каноническим блоком не выше finalized. Не хранит подписанные байты или ключи. Отдельный тестовый журнал, не изменяет mainnet USDT chat journal. Консервативная блокировка при сбое непосредственно после reservation может потребовать ручной диагностики; автоматического сброса нет. Один процесс приложения; не координирует другие устройства. 
- Asset inventory: обнаружение обычных SPL и Token-2022 аккаунтов по владельцу (Solana mainnet genesis, exact uint64, mint/program/owner, дедупликация), без внешних метаданных и без включения непроверенных токенов в USD итог. Возможные коллекционные токены не объявляются верифицированными NFT.
- Bitcoin UTXO: read-only список по одному уже выведенному адресу через Esplora, без утверждения о расходуемости, без подписи и без PSBT.
- Token permissions: чтение allowance(owner,spender) известных ERC-20 с двух RPC, предупреждение max uint256. Не отзывает разрешения и не является вердиктом о доверии к контракту.
- Локальная защита от address poisoning: совпадение первых/последних 4 символов при различии адреса с адресной книгой, блок на проверке и отправке; это эвристика, не глобальная антифишинговая база.

## Проверки выполненные здесь
- 15 pytest tests passed (test_wallet_sepolia_inventory.py, test_wallet_network_expansion.py, test_wallet_network_token_engine.py, test_wallet_security_foundation.py, test_wallet_evm_stage7.py; Swift 5/6, подставные RPC и RLP-фикстуры). Расширенный прогон не завершён по лимиту, не объявляется успешным.
- Swift frontend parse новых iOS-файлов и изменённых экранов. Linux не может собрать Wallet Core iOS, SwiftUI, LocalAuthentication или проверить работу Face ID. Добавлен XCTest для подписи публичным fixture-ключом, но здесь не запускался.
- Не выполнены: Xcode build, тест на iPhone, funded Sepolia live E2E, независимый аудит. Для реального теста использовать отдельный тестовый кошелёк и исключительно test ETH; не импортировать рабочую seed-фразу. Не тестировать на реальных средствах.

## Незакрытые требования
- Mainnet ETH/ERC-20 самостоятельная отправка: прежнее ограничение не снято. Sepolia native ETH реализован в коде, но не подтверждён живой транзакцией.
- SOL/BTC: чтение, без создания, подписи и отправки.
- Единый полный мультичейн-портфель и проверенные NFT: не завершены.
- Swap/Bridge: проверяемые котировки предыдущего блока сохранены; реальное исполнение не реализовано.
- Разрешения: чтение, без revoke. Антифишинг: только локальная эвристика, без внешнего threat feed.
- Xcode / device / live testnet / audit: обязательные release gates.

Справочные API: https://solana.com/docs/rpc/http/gettokenaccountsbyowner ; https://solana.com/docs/payments/how-payments-work ; https://github.com/Blockstream/esplora/blob/master/API.md ; https://docs.1rpc.io/overview/supported-networks .

## Установка
Один ZIP console-update-spyder-wallet-testnet-inventory-5a.zip в корень репозитория. Предыдущие патчи включены. .github/workflows и project.yml не меняются. После распаковки запустить существующий iOS CI и XCTest; затем проверить отдельным тестовым кошельком на устройстве.
