import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def source(path):
    return (ROOT / path).read_text(encoding='utf-8')

class Block34Integrity(unittest.TestCase):
    def test_chat_client_requires_v2(self):
        s = source('Console/ChatLive/SpyderChatService.swift')
        self.assertIn('health.version == 2, health.e2ee', s)
        self.assertIn('"/v2/messages"', s)
        self.assertNotIn('perform("/v1/messages', s)
        self.assertIn('SpyderMessageCrypto.verifyAndPin', s)

    def test_server_refuses_plaintext(self):
        # Chat Unified moved secure handling into chat.mjs, while index.mjs
        # is now a router. Verify the real enforcement module, not a stale path.
        router = source('server/src/index.mjs')
        s = source('server/src/chat.mjs')
        self.assertIn('chatWorker.fetch', router)
        self.assertIn('plaintext_protocol_retired', s)
        self.assertIn("if(path==='/v1/messages')", s)
        self.assertIn('!Object.hasOwn(value,\'text\')', s)
        self.assertIn("'encmsgs:'", s)

    def test_e2ee_is_separate_from_wallet_keys(self):
        s = source('Console/Security/SpyderMessageCrypto.swift')
        self.assertIn('kSecAttrAccessibleWhenUnlockedThisDeviceOnly', s)
        self.assertIn('Curve25519.KeyAgreement.PrivateKey', s)
        self.assertIn('Curve25519.Signing.PrivateKey', s)
        self.assertIn('ChaChaPoly.seal', s)
        self.assertNotIn('WalletVault', s)

    def test_activity_stale_guard_and_allowlist(self):
        s = source('Console/WalletCore/WalletActivityHistory.swift')
        self.assertIn('guard id == generation', s)
        self.assertIn('WalletTokenCatalog.verifiedEthereumToken', s)
        self.assertIn('getSignaturesForAddress', s)
        self.assertIn('https://mempool.space/api/address/', s)

    def test_mainnet_send_still_disabled(self):
        s = source('Console/Features/Wallet/WalletSendFlowView.swift')
        self.assertIn('Mainnet', s)
        self.assertNotIn('eth_sendRawTransaction', s)

    def test_source_locales_present(self):
        for loc in ('ru','en'):
            data = source(f'Console/Resources/{loc}.lproj/Localizable.strings')
            self.assertIn('"История операций"', data)
            self.assertIn('"Заблокировать контакт"', data)

if __name__ == '__main__': unittest.main()
