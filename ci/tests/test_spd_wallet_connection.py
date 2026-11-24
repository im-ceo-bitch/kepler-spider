"""Static regression gates; real device and HTTPS gateway still need acceptance."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
def read(path): return (ROOT / path).read_text()
class SPDConnectionChecks(unittest.TestCase):
    def test_visible_even_before_configuration(self):
        h = read('Console/Features/Wallet/WalletHomeView.swift')
        self.assertRegex(h, r'portfolioCard\s+quickActions\s+spdAssetEntry')
        self.assertIn('Button("Подключить SPD")', h)
        self.assertIn('WalletReceiveView(spd: true)', h)
        self.assertIn('WalletTransferView(isRequest: false', h)
    def test_verified_before_persisting_credentials(self):
        s = read('Console/SpiderDevnet/SpiderDevnetStore.swift')
        config = s.split('func configure(', 1)[1].split('private func client()', 1)[0]
        self.assertLess(config.index('candidate.status()'), config.index('SpiderDevnetCredentials.save('))
        self.assertLess(config.index('candidate.status()'), config.index('UserDefaults.standard.set(configData'))
        self.assertIn('previous.origin == trimmedOrigin', config)
        self.assertIn('previous.genesisHash == genesis', config)
        self.assertIn('pending == nil, !sending, !configuring', config)
    def test_selected_wallet_and_epoch_checks(self):
        s = read('Console/SpiderDevnet/SpiderDevnetStore.swift')
        self.assertEqual(s.count('WalletVault.revealForSigning(id: selectedWalletID'), 2)
        self.assertNotIn('WalletVault.revealForBackup()', s)
        self.assertIn('epoch == sessionEpoch, address == transfer.from, pending == nil', s)
        self.assertIn('func selectAccount(_ id: String)', s)
        app = read('Console/ConsoleApp.swift')
        self.assertIn('spiderDevnet.selectAccount(id)', app)
        self.assertIn('if !unlocked { spiderDevnet.clear() }', app)
    def test_transfer_needs_exact_amount_and_global_pending_guard(self):
        s = read('Console/Features/Wallet/WalletTransferView.swift')
        self.assertIn('units.addingReportingOverflow(fee)', s)
        self.assertIn('total <= balance', s)
        self.assertIn('spider.pending == nil', s)
        self.assertIn('spider.walletID == spdAccess.activeWalletID', s)
        self.assertIn('spider.pendingForAddress != nil', s)
    def test_unknown_balance_and_expired_not_success(self):
        s = read('Console/SpiderDevnet/SpiderDevnetStore.swift')
        self.assertIn('account.height > pending.expiryHeight', s)
        self.assertIn('latestExpired = pending.id', s)
        self.assertIn('connected = false\n                balanceAtomic = nil', s)
        h = read('Console/Features/Wallet/WalletHomeView.swift')
        self.assertIn('spider.connected ? spider.balanceText + " SPD" : "— SPD"', h)
        self.assertIn('Срок перевода истёк. Транзакция не подтверждена.', h)
if __name__ == '__main__': unittest.main()
