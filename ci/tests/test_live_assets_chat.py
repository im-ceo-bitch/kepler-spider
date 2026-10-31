import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class LiveAssetsChatChecks(unittest.TestCase):
    def test_real_asset_reads_public_only(self):
        source = (ROOT / 'Console/WalletCore/WalletPublicAssets.swift').read_text()
        for value in ('eth_getBalance', 'getBalance', 'blockstream.info/api/address',
                      'simple/price', '0xdac17f958d2ee523a2206206994597c13d831ec7',
                      '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'):
            self.assertIn(value, source)
        self.assertNotIn('WalletVault', source)
        self.assertNotIn('eth_sendRawTransaction', source)

    def test_chat_uses_spyder_not_legacy(self):
        source = (ROOT / 'Console/Features/Chats/LegacyChatRouter.swift').read_text()
        self.assertIn('SpyderDevnetChatsHomeView', source)
        self.assertNotIn('LegacyConsoleChatsView()', source)
        client = (ROOT / 'Console/ChatLive/SpyderChatService.swift').read_text()
        for route in ('/v1/profile/username', '/v1/users/search', '/v1/invites', '/v1/messages'):
            self.assertIn(route, client)

    def test_wallet_version_does_not_change(self):
        source = (ROOT / 'project.yml').read_text()
        self.assertIn('MARKETING_VERSION: "1.0"', source)


if __name__ == '__main__':
    unittest.main()
