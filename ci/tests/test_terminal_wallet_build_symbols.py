"""Tests terminal bridge uses present symbols; never forbids a valid Spyder Sonic component."""
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
class TerminalWalletBuildSymbols(unittest.TestCase):
    def test_chat_client_only_calls_available_api(self):
        path=ROOT/'Console/Features/Chats/SpyderChatTerminalView.swift'
        code=path.read_text(encoding='utf-8')
        self.assertNotIn('chat.updateDisplayName(',code)
        self.assertIn('case "profile.name.set":',code)
        self.assertIn('сервер Chat v2 не поддерживает',code)
    def test_message_sound_and_haptics_have_real_implementation(self):
        chat=(ROOT/'Console/Features/Chats/ChatDetailView.swift').read_text(encoding='utf-8')
        terminal=(ROOT/'Console/Features/Chats/SpyderChatTerminalView.swift').read_text(encoding='utf-8')
        self.assertTrue('SpyderSonicPlayer.shared.playSent()' in chat or
                        'UINotificationFeedbackGenerator().notificationOccurred(.success)' in chat)
        self.assertIn('UINotificationFeedbackGenerator().notificationOccurred(.success)',terminal)
        if 'SpyderSonicPlayer' in chat or 'SpyderSonicPlayer' in terminal:
            sound=(ROOT/'Console/ChatLive/SpyderSonicPlayer.swift').read_text(encoding='utf-8')
            self.assertIn('final class SpyderSonicPlayer',sound)
    def test_terminal_package_remains_linked(self):
        project=(ROOT/'project.yml').read_text(encoding='utf-8')
        self.assertIn('path: Packages/SpyderTerminalKit',project)
        self.assertIn('product: SpyderTerminalKit',project)
if __name__ == '__main__': unittest.main()
