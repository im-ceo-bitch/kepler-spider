"""Block 5/6 wallet market-catalog regressions. Not a substitute for xcodebuild."""
from pathlib import Path
import subprocess
import shutil
import unittest

ROOT = Path(__file__).resolve().parents[2]
HOME = (ROOT / 'Console/Features/Wallet/WalletHomeView.swift').read_text()
UI = (ROOT / 'Console/Features/Wallet/WalletCatalogViews.swift').read_text()
STORE = (ROOT / 'Console/WalletCore/WalletCatalogStore.swift').read_text()
MODEL = (ROOT / 'Console/WalletCore/WalletCatalogModels.swift').read_text()


class WalletCatalogBlock56Tests(unittest.TestCase):
    def test_switch_inside_wallet_below_actions(self):
        self.assertLess(HOME.index('quickActions\n'), HOME.index('walletSectionPicker\n'))
        self.assertIn('WalletCatalogSection(catalog: catalog)', HOME)
        self.assertIn('assetsSection', HOME)
        self.assertIn('recentSection', HOME)
        self.assertIn('@AppStorage("spyder.wallet.home.section")', HOME)

    def test_real_bounded_market_api(self):
        self.assertIn('api.coingecko.com/api/v3/coins/markets', STORE)
        self.assertIn('"per_page", value: String(Self.maximumCoins)', STORE)
        self.assertIn('"sparkline", value: "true"', STORE)
        self.assertIn('static let maximumCoins = WalletCatalogPagination.maximumCoins', STORE)
        self.assertIn('static let disclosureStep = WalletCatalogPagination.step', STORE)
        self.assertIn('"page", value: "1"', STORE)
        self.assertIn('displayedCount = 50', STORE)
        self.assertIn('func showMore()', STORE)
        self.assertNotIn('maxPages = 5', STORE)
        self.assertNotIn('perPage = 100', STORE)
        self.assertIn('if http.statusCode == 429', STORE)
        self.assertIn('chartRetryAfter', STORE)
        self.assertNotIn('seedPhrase', STORE)
        self.assertNotIn('privateKey', STORE)

    def test_search_favorites_and_real_charts(self):
        self.assertIn('TextField("Поиск BTC, ETH, XRP…", text: $query)', UI)
        self.assertIn('@AppStorage("spyder.wallet.catalog.favorites")', UI)
        self.assertIn('LazyVStack(spacing: 0)', UI)
        self.assertIn('WalletCatalogSparkline', UI)
        self.assertIn('LineMark(', UI)
        self.assertIn('proxy.value(atX:', UI)
        self.assertIn('WalletLiveStageView(ticker: coin.symbol)', UI)
        self.assertIn('WalletCatalogPagination.matches(coin, query: query)', UI)
        self.assertIn('WalletCatalogPagination.visible(matches, count: catalog.displayedCount, filtering: filtering)', UI)
        self.assertIn('catalog.showMore()', UI)
        self.assertIn('Text("Открыть ещё")', UI)
        self.assertIn('LIVE · Coinbase', UI)
        self.assertIn('live.tick(coin.symbol)', UI)

    def test_no_fabricated_data_or_supported_network_claims(self):
        self.assertIn('guard validID(item.id)', MODEL)
        self.assertIn('WalletCatalogDecoder.validID(id)', STORE)
        self.assertIn('isFinite', MODEL)
        self.assertIn('providerUpdatedAt', MODEL)
        self.assertIn('не означает поддержку хранения', UI)
        self.assertNotIn('77_889', MODEL + UI + STORE)

    def test_bilingual_translations(self):
        for locale in ('ru', 'en'):
            strings = (ROOT / f'Console/Resources/{locale}.lproj/Localizable.strings').read_text()
            for key in ('Криптовалюты', 'Монеты не найдены', 'Избранное', 'Рыночная цена USD',
                        'Открыть ещё', 'Показано %d из %d', 'Топ-250 по капитализации · поиск по всему списку'):
                self.assertIn('"' + key + '" =', strings)

    def test_provider_snapshot_and_disclosure_are_separate(self):
        self.assertIn('max(0, min(count, maximumCoins))', MODEL)
        self.assertIn('static let maximumCoins = 250', MODEL)
        self.assertIn('static let step = 50', MODEL)
        self.assertIn('WalletCatalogPagination.nextVisibleCount', STORE)
        self.assertIn('https://api.coingecko.com/api/v3/coins/markets', STORE)
        self.assertIn('spyder-market-catalog-top250-v2.json', STORE)
        self.assertIn('if selectedSection == WalletHomeSection.cryptocurrencies.rawValue', HOME)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift unavailable')
    def test_swift_foundation_models_typecheck(self):
        files = ['Console/WalletCore/WalletCatalogModels.swift']
        subprocess.run(['swiftc', '-typecheck', *(str(ROOT / f) for f in files)],
                       check=True, capture_output=True, timeout=40)


if __name__ == '__main__':
    unittest.main()
