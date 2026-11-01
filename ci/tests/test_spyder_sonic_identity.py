"""Static integration gates for Spyder Sonic and unified identity settings."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
def source(path):
    return (ROOT / path).read_text(encoding='utf-8')

class SonicIdentityChecks(unittest.TestCase):
    def test_custom_sounds_are_short_pcm_caf(self):
        for name in ('spyder_receive', 'spyder_sent', 'spyder_connect'):
            audio = (ROOT / 'Console' / 'Resources' / f'{name}.caf').read_bytes()
            self.assertEqual(audio[:4], b'caff')
            self.assertLess(len(audio), 150000)

    def test_custom_tones_only_in_authenticated_server_push(self):
        push = source('server/src/apns.mjs')
        server = source('server/src/chat.mjs')
        self.assertIn('spyder_receive.caf',push)
        self.assertIn('spyder_connect.caf',push)
        self.assertIn("tone === 'mute'",push)
        self.assertIn("if(!me)return bad('unauthorized',401)",server)
        self.assertIn("path==='/v2/push/preferences'",server)
        self.assertIn("path==='/v2/push/test'",server)
        self.assertIn("pushlast:'+recipient",server)
        self.assertIn("path==='/v2/profile/name'",server)

    def test_identity_hub_is_shared_and_does_not_create_fake_profiles(self):
        root = source('Console/WalletRootView.swift')
        chats = source('Console/Features/Chats/ChatsHomeView.swift')
        hub = source('Console/Features/Settings/SpyderIdentityHubView.swift')
        self.assertIn('case .profile:\n            SpyderIdentityHubView()',root)
        self.assertIn('onProfile()',chats)
        self.assertIn('case .identity:',root)
        self.assertNotIn('.sheet(isPresented: $showingPrivacy)',chats)
        self.assertIn('SpyderNotificationSettingsView()',hub)
        self.assertNotIn('addIdentity(',hub)

    def test_push_registration_keeps_user_preference_and_no_chat_plaintext(self):
        ios = source('Console/ChatLive/SpyderChatService.swift')
        delegate = source('Console/ChatLive/SpyderPushAppDelegate.swift')
        self.assertIn('let sound: String',ios)
        self.assertIn('func sendTestPush()',ios)
        self.assertIn('func refreshPushDiagnostics()',ios)
        self.assertIn('func updateDisplayName(',ios)
        self.assertIn('spyderChatDeviceToken',delegate)
        self.assertIn('spyderChatOpenRequested',delegate)
        self.assertNotIn('privateKey',delegate)

if __name__=='__main__':
    unittest.main()
