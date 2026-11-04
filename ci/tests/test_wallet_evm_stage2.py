"""Block 7 stage 2: compile and execute public-data intent tests; no key exfiltration or send."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'Console/WalletCore'

class EVMStage2Tests(unittest.TestCase):
    def test_unsigned_intents_compiled_and_executed(self):
        swift = shutil.which('swiftc')
        if not swift:
            self.skipTest('swiftc unavailable; must run Xcode build-only CI')
        with tempfile.TemporaryDirectory() as d:
            executable = str(Path(d) / 'unsigned-intents')
            subprocess.run([swift, str(CORE/'WalletEVMPreflight.swift'),
                            str(CORE/'WalletEVMUnsignedIntent.swift'),
                            str(ROOT/'ci/tests/wallet_evm_unsigned_driver.swift'),
                            '-o', executable], check=True, timeout=90)
            process = subprocess.run([executable], check=True, capture_output=True, text=True, timeout=20)
            self.assertIn('PASS EVM stage 2 unsigned intent', process.stdout)

    def test_offline_signer_fails_closed_by_default(self):
        signer = (CORE/'WalletEVMOfflineSigner.swift').read_text()
        flow = (ROOT/'Console/Features/Wallet/WalletSendFlowView.swift').read_text()
        self.assertIn('WalletVault.revealForSigning(id: walletID,', signer)
        self.assertIn('derived.caseInsensitiveCompare(intent.sender)', signer)
        self.assertIn('intent.ensureFresh()', signer)
        self.assertIn('AnySigner.sign(input: signingInput, coin: .ethereum)', signer)
        self.assertIn('$0.txMode = .enveloped', signer)
        self.assertIn('$0.chainID = Data([1])', signer)
        self.assertNotIn('WalletEVMOfflineSigner', flow)
        for prohibited in ('eth_sendRawTransaction', 'eth_sendTransaction', 'URLSession', 'UserDefaults', 'UIPasteboard'):
            self.assertNotIn(prohibited, signer)
        self.assertIn('showUnavailable = true', flow)
        self.assertIn('canSendUSDT', flow)

    def test_signed_vector_runs_only_in_xcode_and_no_real_secrets(self):
        test = (ROOT/'Tests/WalletEVMSigningTests.swift').read_text()
        self.assertIn('AnySigner.sign(input: input, coin: .ethereum)', test)
        self.assertIn('02f8b00180847735940084b2d05e00', test)
        self.assertNotIn('WalletVault.', test)
        self.assertNotIn('eth_sendRawTransaction', test)

    def test_xcodegen_sources_include_implementation(self):
        spec = (ROOT/'project.yml').read_text()
        self.assertIn('- path: Console', spec)
        self.assertIn('- path: Tests', spec)
        self.assertIn('package: WalletCore', spec)

if __name__ == '__main__': unittest.main()
