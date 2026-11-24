from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class WalletSecurityFoundationTests(unittest.TestCase):
    def test_swift_vectors(self):
        compiler = shutil.which('swiftc')
        if not compiler:
            self.skipTest('Swift compiler unavailable')
        files = ['Console/Security/WalletUnlockGate.swift',
                 'Console/WalletCore/WalletAddressValidator.swift',
                 'Console/WalletCore/WalletEVMKeccak256.swift',
                 'ci/tests/wallet_security_foundation_driver.swift']
        with tempfile.TemporaryDirectory() as tmp:
            for version in ('5', '6'):
                binary = Path(tmp) / ('security-' + version)
                subprocess.run([compiler, '-swift-version', version, *[str(ROOT / p) for p in files], '-o', str(binary)], check=True, timeout=60)
                result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('Wallet security foundation passed', result.stdout)

    def test_production_wiring(self):
        vault = (ROOT / 'Console/Security/WalletVault.swift').read_text()
        self.assertIn('unlockGate.cancel()', vault)
        self.assertIn('unlockContext?.invalidate()', vault)
        self.assertIn('guard self.unlockGate.finish(attempt)', vault)
        signer = (ROOT / 'Console/WalletCore/WalletEVMOfflineSigner.swift').read_text()
        self.assertLess(signer.index('WalletAddressValidator.check(intent.recipient'), signer.index('WalletVault.revealForSigning'))
        book = (ROOT / 'Console/WalletCore/WalletAddressBook.swift').read_text()
        self.assertIn('legacyStorage: true', book)
        self.assertIn('WalletAddressValidator.sameAddress', book)

if __name__ == '__main__':
    unittest.main()
