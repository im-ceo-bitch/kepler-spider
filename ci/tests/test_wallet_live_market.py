"""Static gates for the public, non-custodial Coinbase live feed (not Xcode)."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class LiveMarketGates(unittest.TestCase):
    def test_socket_lifetime_and_allowlist(self):
        source = (ROOT / 'Console/WalletCore/WalletLiveMarket.swift').read_text()
        app = (ROOT / 'Console/ConsoleApp.swift').read_text()
        for symbol in ('BTC-USD', 'ETH-USD', 'SOL-USD'):
            self.assertIn(symbol, source)
        self.assertIn('ws-feed.exchange.coinbase.com', source)
        self.assertIn('backoff', source)
        self.assertIn('socket.cancel', source)
        self.assertIn('Task.isCancelled', source)
        self.assertIn('incoming.timestamp <= old.timestamp', source)
        self.assertIn('walletAccess.lock()', app)
        self.assertIn('await liveMarket.run()', app)
        self.assertIn('liveMarket.stop()', app)
        for secret in ('WalletVault', 'mnemonic', 'seedPhrase', 'privateKey'):
            self.assertNotIn(secret, source)

    def test_interaction_and_sources(self):
        chart = (ROOT / 'Console/Features/Wallet/WalletMarketViews.swift').read_text()
        self.assertIn('chartOverlay', chart)
        self.assertIn('DragGesture(minimumDistance: 0)', chart)
        self.assertIn('RuleMark', chart)
        self.assertIn('PointMark', chart)
        self.assertIn('changeColor(for: points)', chart)
        self.assertIn('Color.green', chart)
        self.assertIn('Color.red', chart)
        self.assertIn('LIVE · Coinbase', chart)
        self.assertIn('История: CoinGecko', chart)

if __name__ == '__main__': unittest.main()
