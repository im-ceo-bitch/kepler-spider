"""Static release gates for Chat Experience: no protocol change, honest UX."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

def read(relative):
    return (ROOT / relative).read_text(encoding="utf-8")

class SpyderChatExperienceTests(unittest.TestCase):
    def test_view_uses_live_encrypted_store(self):
        view = read('Console/Features/Chats/ChatDetailView.swift')
        self.assertIn('chat.sendMessage(to: contact.id, text: text)', view)
        self.assertIn('await chat.loadMessages(peer: contact.id)', view)
        self.assertIn('if await chat.sendMessage(', view)
        self.assertNotIn('Text("✓✓")', view)

    def test_accessible_reduced_motion(self):
        view = read('Console/Features/Chats/ChatDetailView.swift')
        wallpaper = read('Console/Features/Chats/SpyderChatExperience.swift')
        self.assertNotIn('TimelineView', view)
        self.assertIn('accessibilityReduceMotion', wallpaper)
        self.assertIn('isLowPowerModeEnabled', wallpaper)
        self.assertNotIn('withAnimation(', view)

    def test_local_reactions_never_pretend_to_sync(self):
        view = read('Console/Features/Chats/ChatDetailView.swift')
        appearance = read('Console/Features/Chats/SpyderChatExperience.swift')
        self.assertNotIn('SpyderLocalChatReactions.toggle', view)
        self.assertNotIn('ForEach(SpyderLocalChatReactions', view)
        self.assertIn('local-only', appearance)
        self.assertNotIn('sendReaction(', view)
        self.assertNotIn('sendMessage(to: contact.id, text: emoji)', view)

    def test_global_and_individual_wallpaper_settings(self):
        prefs = read('Console/Features/Chats/SpyderChatExperience.swift')
        profile = read('Console/Features/Settings/SpyderIdentityHubView.swift')
        detail = read('Console/Features/Chats/ChatDetailView.swift')
        for token in ('case void, web, orbit, cyber, constellation',
                      'static func reset(peer: String, persona: String? = nil',
                      'func save(_ value: SpyderChatAppearance, peer: String? = nil, persona: String? = nil'):
            self.assertIn(token, prefs)
        self.assertNotIn('SpyderChatAppearanceSettingsView(', profile)
        self.assertNotIn('SpyderChatAppearanceSettingsView(', detail)

    def test_no_wallet_or_server_protocol_in_styling_component(self):
        prefs = read('Console/Features/Chats/SpyderChatExperience.swift')
        self.assertNotIn('URLSession', prefs)
        self.assertNotIn('SpyderMessageCrypto', prefs)
        self.assertNotIn('WalletAccess', prefs)

if __name__ == '__main__':
    unittest.main()
