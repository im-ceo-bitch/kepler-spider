# Spyder Wallet — Market Data Engine (01.11.2026)

## Интеграция

Изменения основаны на `kepler-spider-main 3.zip` с наложенным `console-update-spyder-wallet-portfolio-20261101.zip`. Обновление накопительное относительно `kepler-spider-main 3.zip`, не включает изменения чата, MessageChain, Cloudflare, seed/keychain и GitHub workflow.

- Пять явно разрешённых активов CoinGecko: Bitcoin, Ethereum, Solana, Tether USD (Ethereum ERC-20), USD Coin (Ethereum ERC-20).
- `GET https://api.coingecko.com/api/v3/coins/markets` — рыночная цена USD, 24h %, `last_updated`, CDN URL логотипов. Никаких адресов кошелька и приватных данных.
- `GET https://api.coingecko.com/api/v3/coins/{id}/market_chart?vs_currency=usd&days={1,7,30,90}` — реальные точки графиков без фиктивных значений.
- 90 секунд между попытками автоматического обновления котировок при активном приложении, 20 секунд минимальный интервал между ручными запросами, cooldown после HTTP 429. Графики загружаются по запросу и сохраняются в публичный кэш: 5 минут для 1Д, 30 минут для длинных периодов.
- Валидируются положительные конечные значения цены, время обновления, допустимые CoinGecko asset ID и HTTPS-домены логотипов. Устаревшие котировки (>15 минут) помечаются как устаревшие; при недоступности API не генерируются фальшивые курсы.
- Swift Charts на страницах BTC/ETH/SOL/USDT/USDC; CoinGecko CDN logos через AsyncImage с локальным fallback; market strip на Wallet Home; информация о времени котировки и источнике.
- Существующий компонент чтения балансов Mainnet сохранён. Сам движок отправки транзакций **не изменён** и остаётся заблокированным.

## Ограничения

1. Это **polling**, не биржевой WebSocket / гарантированное real-time. Цена может запаздывать, а источник CoinGecko ограничивает keyless вызовы по IP и тарифу. Для большого production-трафика потребуется собственный серверный market-data gateway с ключом API и кэшированием, а также коммерческие условия CoinGecko.
2. Часть диапазонов графиков может быть недоступна в бесплатном доступе, при API-ошибке показывается ошибка или сохранённый график с маркировкой.
3. Логотипы зависят от доступности CDN и могут показать встроенный символ офлайн.
4. Это **не** order-book, не цены исполнения сделок, не crypto-onramp и не движок отправки.
5. Данные курса публичные и кэшируются на устройстве. Seed-фразы/адреса пользователя не отправляются market-data сервису.

## Проверка перед TestFlight

В репозитории: `python3 -m unittest discover -s ci/tests -v`.

В macOS Xcode CI до TestFlight **обязательно**: `xcodegen generate`, `xcodebuild -project Console.xcodeproj -scheme Console -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` (и затем UI-тесты на подходящем симуляторе/устройстве). Проверить Swift Charts iOS 17+, iPhone 11, iPhone 13 mini, тёмную тему, Reduce Motion, Safe Area, работу при 429 и офлайн.

Локальные проверки без Xcode: Python CI, `swiftc -frontend -parse` всех Swift-файлов, Swift `-typecheck` для новой Foundation market-model и store (с Combine shim в Linux), автономный тест JSON-декодера. **Полный Xcode build здесь недоступен; успешная macOS-компиляция не утверждается.**
