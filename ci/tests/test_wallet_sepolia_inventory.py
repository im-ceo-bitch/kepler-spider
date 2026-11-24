from pathlib import Path
import shutil, subprocess, tempfile, unittest
ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'Console/WalletCore'
class SepoliaInventoryTests(unittest.TestCase):
    def test_pure_swift_vectors(self):
        if not shutil.which('swiftc'): self.skipTest('Swift compiler unavailable')
        files = ['WalletEVMPreflight.swift','WalletEVMUnsignedIntent.swift','WalletEVMKeccak256.swift','WalletEVMSignedEnvelopeGuard.swift','WalletNetworkExpansion.swift','WalletNetworkTokenEngine.swift','WalletAddressValidator.swift','WalletSepoliaTransfer.swift','WalletPublicInventory.swift']
        with tempfile.TemporaryDirectory() as tmp:
            for version in ['5','6']:
                binpath = Path(tmp)/('test'+version)
                subprocess.run(['swiftc','-swift-version',version,*[str(CORE/f) for f in files],str(ROOT/'ci/tests/wallet_sepolia_inventory_driver.swift'),'-o',str(binpath)],check=True,timeout=90)
                result = subprocess.run([str(binpath)],capture_output=True,text=True,timeout=30)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertIn('PASS Sepolia and inventory',result.stdout)
    def test_publication_is_testnet_only(self):
        sign = (CORE/'WalletSepoliaSigning.swift').read_text()
        self.assertIn('WalletEVMSignedEnvelopeGuard.sepoliaProof',sign)
        self.assertIn('WalletEthereumSignature.recoveredAddress',sign)
        self.assertLess(sign.index('journal.reserve(record)'),sign.index('"eth_sendRawTransaction"'))
        self.assertEqual(sign.count('"eth_sendRawTransaction"'),1)
        self.assertIn('WalletSepoliaIntent.chainID',sign)
        self.assertIn('stillAuthorized()',sign)
        self.assertNotIn('privateKey', (CORE/'WalletPublicInventory.swift').read_text())
    def test_suspicious_recipient_gate(self):
        send=(ROOT/'Console/Features/Wallet/WalletSendFlowView.swift').read_text()
        self.assertIn('recipientValid, !suspiciousRecipient',send)
        self.assertIn('recipientContextValid, !suspiciousRecipient',send)
        self.assertIn('!suspiciousRecipient',(ROOT/'Console/Features/Wallet/WalletSepoliaTransferView.swift').read_text())
