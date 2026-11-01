"""Native dual-theme live market regression gates. These do NOT replace xcodebuild."""
import platform
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class DualThemeLiveGates(unittest.TestCase):
    def test_live_market_ui_and_global_theming(self):
        ui = (ROOT / 'Console/Features/Wallet/WalletLiveStageView.swift').read_text()
        home = (ROOT / 'Console/Features/Wallet/WalletHomeView.swift').read_text()
        preview = (ROOT / 'Console/Features/Wallet/WalletMarketViews.swift').read_text()
        app = (ROOT / 'Console/ConsoleApp.swift').read_text()
        for token in ('WalletAppearance.allCases', 'spyder.wallet.appearance',
                      '.chartOverlay', 'AxisMarks(position: .trailing',
                      'PointMark', 'DragGesture(minimumDistance: 0)',
                      'Coinbase Exchange', 'walletMarket'):
            if token == 'walletMarket':
                continue
            self.assertIn(token, ui)
        self.assertIn('.preferredColorScheme(preferredScheme)', app)
        self.assertIn('WalletLiveStageView(ticker: selection.ticker)', home)
        self.assertIn('WalletLiveStageView(ticker: ticker)', preview)
        self.assertIn('reduceMotion', ui)
        self.assertIn('window.isShort', ui)
        self.assertNotIn('WalletVault', ui)

    def test_short_candles_api_and_bounds(self):
        source = (ROOT / 'Console/WalletCore/WalletLiveCandles.swift').read_text()
        decoder = (ROOT / 'Console/WalletCore/WalletLiveCandleDecoder.swift').read_text()
        self.assertIn('api.exchange.coinbase.com/products/', source)
        self.assertIn('value: "60"', source)
        self.assertIn('timeIntervalSince(attempt[ticker]', source)
        self.assertIn('try Task.checkCancellation()', source)
        self.assertIn('close.isFinite, close > 0', decoder)
        self.assertIn('ordered.suffix(125)', decoder)
        self.assertNotIn('mnemonic', source)
        self.assertNotIn('privateKey', source)

    def test_candle_decoder_typechecks_with_real_compiler(self):
        if not shutil.which('swiftc'):
            self.skipTest('Requires swiftc or Xcode CI')
        command = ['swiftc', '-swift-version', '5', '-typecheck',
                   str(ROOT / 'Console/WalletCore/WalletMarketModels.swift'),
                   str(ROOT / 'Console/WalletCore/WalletLiveCandleDecoder.swift')]
        result = subprocess.run(command, capture_output=True, text=True, timeout=100)
        self.assertEqual(result.returncode, 0, result.stderr)

if __name__ == '__main__': unittest.main()
