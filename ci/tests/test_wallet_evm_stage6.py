"""Stage 6 double-gated Swift verification, no network transaction/broadcast."""
import subprocess
import tempfile
import shutil
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "Console/WalletCore"

class Stage6Checks(unittest.TestCase):
    def compile_run(self, filenames, flag=False, language='5'):
        if shutil.which('swiftc') is None:
            self.skipTest('Swift compiler unavailable: requires Xcode build gate')
        with tempfile.TemporaryDirectory(prefix='spyder-stage6-') as tmp:
            out = str(Path(tmp) / 'test')
            args = ['swiftc', '-swift-version', language]
            if flag: args.append('-DSPYDER_EVM_RELAY_TESTS')
            args += [str(ROOT / f) for f in filenames] + ['-o', out]
            built = subprocess.run(args, capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            executed = subprocess.run([out], capture_output=True, text=True, timeout=50)
            self.assertEqual(executed.returncode, 0, executed.stdout + executed.stderr)
            self.assertIn('passed', executed.stdout)

    def test_signed_payload_and_restart_journal_swift5(self):
        self.compile_run(['Console/WalletCore/WalletEVMPreflight.swift',
            'Console/WalletCore/WalletEVMUnsignedIntent.swift',
            'Console/WalletCore/WalletEVMKeccak256.swift',
            'Console/WalletCore/WalletEVMSignedEnvelopeGuard.swift',
            'Console/WalletCore/WalletEVMNonceJournal.swift',
            'ci/tests/wallet_evm_stage6_driver.swift'], flag=True)

    def test_signed_payload_and_restart_journal_swift6(self):
        self.compile_run(['Console/WalletCore/WalletEVMPreflight.swift',
            'Console/WalletCore/WalletEVMUnsignedIntent.swift',
            'Console/WalletCore/WalletEVMKeccak256.swift',
            'Console/WalletCore/WalletEVMSignedEnvelopeGuard.swift',
            'Console/WalletCore/WalletEVMNonceJournal.swift',
            'ci/tests/wallet_evm_stage6_driver.swift'], flag=True, language='6')

    def test_sepolia_probe_swift5(self):
        self.compile_run(['Console/WalletCore/WalletEVMSepoliaProbe.swift',
            'ci/tests/wallet_evm_sepolia_driver.swift'])

    def test_sepolia_probe_swift6(self):
        self.compile_run(['Console/WalletCore/WalletEVMSepoliaProbe.swift',
            'ci/tests/wallet_evm_sepolia_driver.swift'], language='6')

    def test_release_broadcast_still_prohibited(self):
        staging = (CORE/'WalletEVMBroadcastStaging.swift').read_text()
        send = (ROOT/'Console/Features/Wallet/WalletSendFlowView.swift').read_text()
        journal = (CORE/'WalletEVMNonceJournal.swift').read_text()
        signer = (CORE/'WalletEVMOfflineSigner.swift').read_text()
        self.assertIn('#if SPYDER_EVM_RELAY_TESTS', staging)
        self.assertIn('#if SPYDER_EVM_RELAY_TESTS', journal)
        self.assertNotIn('eth_sendRawTransaction', send)
        self.assertNotIn('WalletEVMBroadcastStaging', send)
        self.assertIn('WalletEthereumSignature.verify(raw:', signer)
        self.assertIn('try validate(raw: raw, intent: intent)', (CORE/'WalletEVMSignedEnvelopeGuard.swift').read_text())
        self.assertNotIn('URLSession', signer)
        self.assertTrue((ROOT/'Tests/WalletRecoveryParityTests.swift').exists())

    def test_new_files_are_discoverable_by_xcodegen_and_safe(self):
        spec = (ROOT/'project.yml').read_text()
        self.assertIn('- path: Console', spec)
        self.assertIn('- path: Tests', spec)
        for file in ['WalletEVMSignedEnvelopeGuard.swift', 'WalletEVMNonceJournal.swift', 'WalletEVMSepoliaProbe.swift']:
            contents = (CORE/file).read_text()
            self.assertNotIn('revealForBackup', contents)
            self.assertNotIn('eth_sendRawTransaction', contents)
        self.assertNotIn('SPYDER_EVM_RELAY_TESTS', spec)

if __name__ == '__main__':
    unittest.main()
