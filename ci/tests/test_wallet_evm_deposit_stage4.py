"""Read-only, reproducible Ethereum ERC-20 receipt verification security gate."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DepositVerifierGate(unittest.TestCase):
    def test_real_swift_receipt_evidence_vectors(self):
        if not shutil.which('swiftc'):
            self.skipTest('swiftc missing (full iOS Xcode CI is still required)')
        with tempfile.TemporaryDirectory(prefix='spyder-deposit-') as tmp:
            output = Path(tmp) / 'test-deposit'
            source = [
                ROOT / 'Console/WalletCore/WalletEVMPreflight.swift',
                ROOT / 'Console/WalletCore/WalletEVMDepositVerifier.swift',
                ROOT / 'ci/tests/wallet_evm_deposit_driver.swift',
            ]
            compile = subprocess.run(['swiftc', '-swift-version', '5', '-o', str(output), *map(str, source)],
                                     capture_output=True, text=True, timeout=90)
            self.assertEqual(compile.returncode, 0, compile.stderr)
            run = subprocess.run([str(output)], capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertIn('13 cases passed', run.stdout)

    def test_no_confusion_between_indexer_and_rpc_evidence(self):
        verifier = (ROOT / 'Console/WalletCore/WalletEVMDepositVerifier.swift').read_text()
        activity = (ROOT / 'Console/WalletCore/WalletActivityHistory.swift').read_text()
        view = (ROOT / 'Console/Features/Wallet/WalletTransferView.swift').read_text()
        self.assertIn('eth_getTransactionReceipt', verifier)
        self.assertIn('eth_chainId', verifier)
        self.assertIn('eth_getBlockByNumber', verifier)
        self.assertIn('first.amountBaseUnits == other.amountBaseUnits', verifier)
        self.assertIn('to?.caseInsensitiveCompare(address)', activity)
        self.assertIn('Найдено индексатором · проверьте RPC', view)
        self.assertIn('chains.verifiedWalletID == access.activeWalletID', view)
        self.assertIn('independentlyConfirmed', view)
        self.assertNotIn('eth_sendRawTransaction', verifier)


if __name__ == '__main__':
    unittest.main()
