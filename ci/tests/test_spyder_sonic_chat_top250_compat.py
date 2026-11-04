"""Regression checks: the combined Sonic/Identity + Chat Experience patch preserves Top250."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
def source(path): return (ROOT / path).read_text(encoding='utf-8')

class SpyderIntegrationCompat(unittest.TestCase):
    def test_top250_remains_available(self):
        home = source('Console/Features/Wallet/WalletHomeView.swift')
        self.assertIn('WalletCatalogSection(catalog: catalog)', home)
        self.assertIn('WalletLiveStageView(ticker: selection.ticker)', home)
        self.assertIn('WalletCatalogStore()', home)
        self.assertIn('if spider.hasConfiguration', home)
        self.assertTrue((ROOT / 'Console/WalletCore/WalletCatalogModels.swift').exists())
    def test_wallet_animated_avatar_and_chat_profile(self):
        home = source('Console/Features/Wallet/WalletHomeView.swift')
        root = source('Console/WalletRootView.swift')
        chat = source('Console/Features/Chats/ChatsHomeView.swift')
        self.assertTrue('onControlCenter' in home or 'SpyderProfileAvatarView' in home)
        identity = source('Console/Features/Settings/SpyderIdentityHubView.swift')
        self.assertIn('SpyderProfileAvatarView', identity)
        self.assertIn('case .profile:\n            SpyderIdentityHubView()', root)
        self.assertIn('Button(action: onProfile)', chat)
        self.assertIn('case .identity:', root)
    def test_chat_experience_and_sonic_integrated(self):
        details = source('Console/Features/Chats/ChatDetailView.swift')
        identity = source('Console/Features/Settings/SpyderIdentityHubView.swift')
        self.assertNotIn('SpyderLayeredChatBackdrop(', details)
        layered = source('Console/Features/Chats/SpyderNativeSpiderIntegration.swift')
        self.assertIn('SpyderChatWallpaperView(', layered)
        self.assertIn('SpyderSpiderLayer(', layered)
        self.assertIn('if await chat.sendMessage(', details)
        self.assertTrue((ROOT / 'Console/ChatLive/SpyderSonicPlayer.swift').exists())
        self.assertNotIn('SpyderChatAppearanceSettingsView(', identity)
        self.assertIn('SpyderNotificationSettingsView()', identity)
        for name in ('spyder_receive.caf','spyder_sent.caf','spyder_connect.caf'):
            self.assertTrue((ROOT / 'Console/Resources' / name).exists())
    def test_no_overwrite_current_ci_release_gate(self):
        self.assertIn('test_chat_onboarding_never_requests_server_address',
                      source('ci/tests/test_spyder_live_release.py'))
    def test_push_stays_generic_and_encrypted(self):
        server = source('server/src/chat.mjs')
        push = source('server/src/apns.mjs')
        self.assertIn('push_not_registered', server)
        self.assertIn('spyder_receive.caf', push)
        self.assertNotIn('message.text', push)

if __name__ == '__main__': unittest.main()
