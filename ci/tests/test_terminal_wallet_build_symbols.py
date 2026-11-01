"""Guard missing Swift cross-module calls that Linux cannot typecheck without SwiftUI.

The actual iOS build remains mandatory: static tests are not a substitute for Xcode.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class TerminalWalletBuildSymbols(unittest.TestCase):
    def test_chat_client_only_calls_available_api(self):
        code = (ROOT / "Console/Features/Chats/SpyderChatTerminalView.swift").read_text()
        self.assertNotIn("chat.updateDisplayName(", code)
        self.assertIn('case "profile.name.set":', code)
        self.assertIn("сервер Chat v2 не поддерживает", code)

    def test_native_message_player_is_defined_and_only_called_after_ack(self):
        sound = (ROOT / "Console/ChatLive/SpyderSonicPlayer.swift").read_text()
        chat = (ROOT / "Console/Features/Chats/ChatDetailView.swift").read_text()
        bridge = (ROOT / "Console/Features/Chats/SpyderTerminalChatContainer.swift").read_text()
        self.assertIn('final class SpyderSonicPlayer', sound)
        self.assertIn('func playSent()', sound)
        self.assertIn('if succeeded {', chat)
        self.assertIn('SpyderSonicPlayer.shared.playSent()', chat)
        self.assertIn('guard await chat.sendMessage(to: peerID, text: message)', bridge)
        self.assertIn('SpyderSonicPlayer.shared.playSent()', bridge)

    def test_terminal_package_remains_linked(self):
        spec = (ROOT / "project.yml").read_text()
        self.assertIn("path: Packages/SpyderTerminalKit", spec)
        self.assertIn("product: SpyderTerminalKit", spec)

if __name__ == "__main__":
    unittest.main()
