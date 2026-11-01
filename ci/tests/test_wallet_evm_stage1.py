"""Stage 1: fail-closed Ethereum mainnet read-only preflight."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SERVICE = ROOT / 'Console/WalletCore/WalletEVMPreflight.swift'
FLOW = ROOT / 'Console/Features/Wallet/WalletSendFlowView.swift'

class EVMPreflightTests(unittest.TestCase):
    def test_swift_pure_preflight_driver(self):
        swift = shutil.which('swiftc')
        if not swift:
            self.skipTest('Swift compiler unavailable; macOS build-only CI remains required')
        with tempfile.TemporaryDirectory() as work:
            executable = str(Path(work)/'driver')
            driver = ROOT / 'ci/tests/wallet_evm_preflight_driver.swift'
            subprocess.run([swift, str(SERVICE), str(driver), '-o', executable], check=True, timeout=90)
            result = subprocess.run([executable], check=True, capture_output=True, text=True, timeout=30)
            self.assertIn('PASS WalletEVMPreflight', result.stdout)

    def test_rpc_replies_and_security_fail_closed(self):
        swift = shutil.which('swiftc')
        if not swift:
            self.skipTest('Swift compiler unavailable; macOS build remains required')
        with tempfile.TemporaryDirectory() as work:
            executable = str(Path(work)/'rpc-test')
            driver = ROOT / 'ci/tests/wallet_evm_rpc_driver.swift'
            subprocess.run([swift, str(SERVICE), str(driver), '-o', executable], check=True, timeout=90)
            result = subprocess.run([executable], check=True, capture_output=True, text=True, timeout=30)
            self.assertIn('PASS WalletEVM RPC: 6 scenarios', result.stdout)

    def test_quote_never_has_a_broadcast_path(self):
        service = SERVICE.read_text()
        for forbidden in ('eth_sendRawTransaction', 'eth_sendTransaction', 'WalletVault', 'HDWallet(', 'privateKey'):
            self.assertNotIn(forbidden, service)
        self.assertIn('eth_chainId', service)
        self.assertIn('eth_getTransactionCount', service)
        self.assertIn('eth_estimateGas', service)
        self.assertIn('eth_maxPriorityFeePerGas', service)
        self.assertIn('eth_getBalance', service)
        self.assertIn('eth_call', service)
        self.assertIn('guard chain == 1', service)
        self.assertIn('"pending"', service)
        self.assertIn('maxFeePerGas = baseFee * 2 + priority', service)
        self.assertIn('return WalletEVMQuote(', service)

    def test_tokens_allowlisted_and_not_broadcast(self):
        service = SERVICE.read_text()
        self.assertIn('0xdAC17F958D2ee523a2206206994597C13D831ec7', service)
        self.assertIn('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', service)
        self.assertIn('0xa9059cbb', service)
        ui = FLOW.read_text()
        self.assertIn('WalletEVMPreflightClient().quote(', ui)
        self.assertIn('if let quote = evmQuote', ui)
        self.assertIn('showUnavailable = true', ui)
        self.assertNotIn('eth_sendRawTransaction', ui)

    def test_localization(self):
        for lang in ('en', 'ru'):
            value = (ROOT/f'Console/Resources/{lang}.lproj/Localizable.strings').read_text()
            for k in ('Монета Ethereum', 'Проверено по Ethereum Mainnet', 'Проверка сети…'):
                self.assertIn(f'"{k}" = ', value)

    def test_xcodegen_sources_include_new_core(self):
        spec = (ROOT/'project.yml').read_text()
        self.assertIn('- path: Console', spec)
        self.assertIn('SWIFT_VERSION: 5.10', spec)

if __name__ == '__main__': unittest.main()
