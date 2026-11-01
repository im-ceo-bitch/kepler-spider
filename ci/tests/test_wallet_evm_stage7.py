"""Stage 7 signed transaction digest tests independently compared with OpenSSL.

No secrets, no transaction publication, no live network; Xcode signing tests remain mandatory.
"""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'Console/WalletCore'

class Stage7Verification(unittest.TestCase):
    def compile_and_run(self, language):
        if not shutil.which('swiftc'):
            self.skipTest('Swift compiler unavailable')
        files = ['WalletEVMPreflight.swift','WalletEVMUnsignedIntent.swift',
                 'WalletEVMKeccak256.swift', 'WalletEVMSignedEnvelopeGuard.swift']
        with tempfile.TemporaryDirectory(prefix='spyder-stage7-') as tmp:
            binary = str(Path(tmp) / 'vector')
            cmd = ['swiftc', '-swift-version', language] + [str(CORE / f) for f in files] + \
                  [str(ROOT/'ci/tests/wallet_evm_stage7_driver.swift'), '-o', binary]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            ran = subprocess.run([binary], capture_output=True, text=True, timeout=90)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            self.assertIn('Stage 7: Keccak', ran.stdout)
            return ran.stdout

    def test_swift5_keccak_rlp_against_openssl(self):
        output = self.compile_and_run('5')
        if not shutil.which('openssl'):
            self.skipTest('OpenSSL not installed; Swift pinned Ethereum vectors were still checked')
        supported = subprocess.run(['openssl', 'list', '-digest-algorithms'],
                                   capture_output=True, text=True, timeout=10)
        if supported.returncode != 0 or 'KECCAK-256' not in supported.stdout.upper():
            self.skipTest('macOS LibreSSL lacks KECCAK-256; pinned Ethereum Swift vectors checked')
        pairs = [line.split('=',1)[1].split(':',1) for line in output.splitlines() if line.startswith('KECCAK_')]
        self.assertEqual(len(pairs), 9)
        for original, digest in pairs:
            openssl = subprocess.run(['openssl', 'dgst', '-KECCAK-256', '-binary'],
                                     input=bytes.fromhex(original), stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, timeout=10)
            self.assertEqual(openssl.returncode, 0, openssl.stderr)
            self.assertEqual(openssl.stdout.hex(), digest)
        fields = dict(line.split('=',1) for line in output.splitlines() if line.startswith(('TX_RAW=','TX_HASH=','SIGNING_PREIMAGE=','SIGNING_DIGEST=')))
        for raw, hashed in [('TX_RAW','TX_HASH'), ('SIGNING_PREIMAGE','SIGNING_DIGEST')]:
            digest = subprocess.run(['openssl','dgst','-KECCAK-256','-binary'],
                                    input=bytes.fromhex(fields[raw]), stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=10)
            self.assertEqual(digest.returncode, 0, digest.stderr)
            self.assertEqual('0x' + digest.stdout.hex(), fields[hashed])

    def test_swift6_vectors(self):
        self.compile_and_run('6')

    def test_release_still_has_no_broadcast_and_stage7_is_wired(self):
        signer = (CORE/'WalletEVMOfflineSigner.swift').read_text()
        guard = (CORE/'WalletEVMSignedEnvelopeGuard.swift').read_text()
        send = (ROOT/'Console/Features/Wallet/WalletSendFlowView.swift').read_text()
        spec = (ROOT/'project.yml').read_text()
        self.assertIn('WalletEVMSignedEnvelopeGuard.fingerprints', signer)
        self.assertIn('WalletEVMKeccak256.hex(raw)', guard)
        self.assertIn('WalletEVMKeccak256.hex(unsigned)', guard)
        self.assertNotIn('eth_sendRawTransaction', send)
        self.assertNotIn('SPYDER_EVM_RELAY_TESTS', spec)
        self.assertNotIn('URLSession', signer)
        xcode = (ROOT/'Tests/WalletEVMSepoliaSigningTests.swift').read_text()
        self.assertIn('WalletEVMSignedEnvelopeGuard.inspectChainID', xcode)
        self.assertIn('11155111', xcode)
        self.assertIn('AnySigner.sign', xcode)

if __name__ == '__main__':
    unittest.main()
