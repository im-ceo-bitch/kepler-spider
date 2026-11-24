from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'Console/WalletCore'

class NetworkExpansionTests(unittest.TestCase):
    def test_executable(self):
        compiler = shutil.which('swiftc')
        if not compiler:
            self.skipTest('Swift compiler unavailable')
        with tempfile.TemporaryDirectory() as work:
            binary = Path(work) / 'driver'
            subprocess.run([compiler, *(str(CORE / name) for name in ['WalletEVMPreflight.swift','WalletNetworkExpansion.swift','WalletRoutePreview.swift']), str(ROOT / 'ci/tests/wallet_network_expansion_driver.swift'), '-o', str(binary)], check=True, timeout=90)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=30)
            self.assertIn('PASS network expansion', result.stdout)

    def test_no_signing_or_broadcast_in_new_feature(self):
        for path in [CORE / 'WalletNetworkExpansion.swift', CORE / 'WalletRoutePreview.swift', ROOT / 'Console/Features/Wallet/WalletNetworkPortfolioView.swift']:
            text = path.read_text()
            for forbidden in ['eth_sendRawTransaction', 'WalletVault.', 'HDWallet(', 'AnySigner.', 'transactionRequest']:
                self.assertNotIn(forbidden, text)

    def test_access_binding(self):
        text = (ROOT / 'Console/Features/Wallet/WalletHomeView.swift').read_text()
        self.assertIn('chains.verifiedWalletID == access.activeWalletID', text)
        self.assertIn('if !verified { showNetworkPortfolio = false }', text)
        self.assertIn('WalletNetworkPortfolioView(address: address, privacyHidden: privacyHidden)', text)
