"""Stage 5 fail-closed outgoing lifecycle gates (not a mainnet release approval)."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class OutgoingGate(unittest.TestCase):
    def compile_and_run(self, parts, defines=(), expected='passed'):
        if not shutil.which('swiftc'):
            self.skipTest('Swift compiler not installed; Xcode build is separately required')
        with tempfile.TemporaryDirectory(prefix='spyder-evm5-') as tmp:
            binary = Path(tmp) / 'driver'
            cmd = ['swiftc', '-swift-version', '5', *defines, '-o', str(binary),
                   *[str(ROOT / item) for item in parts]]
            build = subprocess.run(cmd, capture_output=True, text=True, timeout=100)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=50)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn(expected, run.stdout)

    def test_outgoing_chain_transaction_and_receipt_vectors(self):
        self.compile_and_run([
            'Console/WalletCore/WalletEVMPreflight.swift',
            'Console/WalletCore/WalletEVMUnsignedIntent.swift',
            'Console/WalletCore/WalletEVMOutgoingTracker.swift',
            'ci/tests/wallet_evm_outgoing_driver.swift'
        ])

    def test_broadcast_not_in_production_and_test_injection_is_safe(self):
        relay = (ROOT / 'Console/WalletCore/WalletEVMBroadcastStaging.swift').read_text()
        self.assertIn('#if SPYDER_EVM_RELAY_TESTS', relay)
        self.assertIn('eth_sendRawTransaction', relay)
        send_flow = (ROOT / 'Console/Features/Wallet/WalletSendFlowView.swift').read_text()
        self.assertNotIn('WalletEVMBroadcastStaging', send_flow)
        self.assertNotIn('eth_sendRawTransaction', send_flow)
        self.compile_and_run([
            'Console/WalletCore/WalletEVMBroadcastStaging.swift',
            'ci/tests/wallet_evm_broadcast_staging_driver.swift'
        ], defines=('-DSPYDER_EVM_RELAY_TESTS',))

    def test_no_secrets_or_transfer_side_effects_in_monitor(self):
        monitor = (ROOT / 'Console/WalletCore/WalletEVMOutgoingTracker.swift').read_text()
        for read in ('eth_chainId', 'eth_getTransactionByHash', 'eth_getTransactionReceipt',
                     'eth_getBlockByNumber', 'eth_blockNumber'):
            self.assertIn(read, monitor)
        for unsafe in ('eth_sendRawTransaction', 'revealForBackup', 'HDWallet(', 'privateKey'):
            self.assertNotIn(unsafe, monitor)
        self.assertIn('observations.count >= 2', monitor)
        self.assertIn('confirmationsRequired', monitor)
        self.assertIn('WalletEVMAsset', monitor)

if __name__ == '__main__':
    unittest.main()
