from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'Console/WalletCore'

class NetworkTokenEngineTests(unittest.TestCase):
    def test_executable(self):
        compiler = shutil.which('swiftc')
        if not compiler:
            self.skipTest('Swift compiler unavailable')
        with tempfile.TemporaryDirectory() as work:
            binary = Path(work) / 'driver'
            subprocess.run([compiler, *(str(CORE / name) for name in ['WalletEVMPreflight.swift','WalletNetworkExpansion.swift','WalletNetworkTokenEngine.swift','WalletRoutePreview.swift']), str(ROOT / 'ci/tests/wallet_network_token_engine_driver.swift'), '-o', str(binary)], check=True, timeout=90)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=30)
            self.assertIn('PASS token engine', result.stdout)

    def test_no_execution(self):
        core = (CORE / 'WalletNetworkTokenEngine.swift').read_text()
        for forbidden in ('eth_sendRawTransaction', 'AnySigner.', 'WalletVault.', 'privateKey', 'transactionRequest'):
            self.assertNotIn(forbidden, core)

    def test_ui_invalidates_background_and_edit(self):
        ui = (ROOT / 'Console/Features/Wallet/WalletNetworkPortfolioView.swift').read_text()
        self.assertIn('if phase != .active { invalidateQuote(); invalidateTransfer()', ui)
        self.assertIn('try request.checkFunding(funding)', ui)
        for field in ['transferAsset', 'transferRecipient', 'transferAmount']:
            self.assertIn('.onChange(of: ' + field + ') { _, _ in invalidateTransfer() }', ui)
        self.assertIn('WalletAddressValidator.check(recipient, for: .ethereum) == .valid', ui)

    def test_vault_revalidates_and_invalidates(self):
        vault = (ROOT / 'Console/Security/WalletVault.swift').read_text()
        self.assertIn('defer { context.invalidate() }', vault)
        self.assertIn('return try canonicalPhrase(phrase).split', vault)
        self.assertIn('seen.insert($0.id).inserted', vault)
