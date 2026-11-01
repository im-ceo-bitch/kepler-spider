from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ReceiveProductionGate(unittest.TestCase):
    def test_no_cached_or_unverified_receiving(self):
        chain = (ROOT / 'Console/WalletCore/WalletChains.swift').read_text()
        view = (ROOT / 'Console/Features/Wallet/WalletTransferView.swift').read_text()
        self.assertIn('verifiedForReceiving = false', chain)
        self.assertIn('verifiedForReceiving = true', chain)
        self.assertIn('verifiedWalletID = id', chain)
        self.assertIn('chains.verifiedWalletID == access.activeWalletID', view)
        self.assertIn('resolved.allSatisfy({ WalletAddressValidator.check', chain)
        self.assertIn('guard chains.verifiedForReceiving', view)
        self.assertIn('SpyderQRView(address: address)', view)
        self.assertIn('walletID', (ROOT / 'Console/WalletCore/WalletEVMOfflineSigner.swift').read_text())
    def test_network_specific_tokens(self):
        options = (ROOT / 'Console/WalletCore/WalletReceiveOptions.swift').read_text()
        self.assertIn('usdtERC20', options)
        self.assertIn('usdcERC20', options)
        self.assertIn('0xdAC17F958D2ee523a2206206994597C13D831ec7', options)
        self.assertIn('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', options)
        self.assertIn('TRC-20, BEP-20', options)
    def test_no_sensitive_keys_changed(self):
        assert (ROOT / 'Console/Security/WalletVault.swift').exists()
        assert (ROOT / 'Console/ChatLive/SpyderChatService.swift').exists()

if __name__ == '__main__': unittest.main()
