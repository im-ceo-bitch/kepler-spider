"""Source-regression checks for Spyder public market engine (not an iOS build)."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(name):
    return (ROOT / name).read_text()


class MarketEngineRegression(unittest.TestCase):
    def test_allowlist_and_data_origin(self):
        models = read('Console/WalletCore/WalletMarketModels.swift')
        engine = read('Console/WalletCore/WalletMarketData.swift')
        for name in ('bitcoin', 'ethereum', 'solana', 'tether', 'usd-coin'):
            self.assertIn(name, models)
        self.assertIn('coin-images.coingecko.com', models)
        self.assertIn('https', models)
        self.assertIn('/coins/markets', engine)
        self.assertIn('/market_chart', engine)
        self.assertIn('quote.isStale()', read('Console/Features/Wallet/WalletMarketViews.swift'))
        self.assertNotIn('WalletVault', engine)
        self.assertNotIn('WalletVault', models)

    def test_no_fake_market_series_and_quote_poll_throttle(self):
        engine = read('Console/WalletCore/WalletMarketData.swift')
        models = read('Console/WalletCore/WalletMarketModels.swift')
        home = read('Console/Features/Wallet/WalletHomeView.swift')
        self.assertIn('try Task.checkCancellation()', engine)
        self.assertIn('retryQuotesAfter', engine)
        self.assertIn('>= 90', engine)
        self.assertIn('isFinite', models)
        self.assertIn('points.count >= 2', models)
        self.assertIn('scenePhase == .active', home)
        self.assertIn('WalletMarketChangeView', home)

    def test_real_swift_charts_for_native_and_erc20(self):
        views = read('Console/Features/Wallet/WalletMarketViews.swift')
        detail = read('Console/Features/Wallet/WalletProductViews.swift')
        self.assertIn('import Charts', views)
        self.assertIn('Chart {', views)
        self.assertIn('WalletMarketPanel(ticker: chain.ticker)', detail)
        self.assertIn('WalletMarketPanel(ticker: token.ticker)', detail)
        self.assertIn('AsyncImage(url:', detail)
        self.assertIn('WalletMarketStore()', read('Console/ConsoleApp.swift'))


if __name__ == '__main__':
    unittest.main()
