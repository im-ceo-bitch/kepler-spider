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

    def test_no_missing_message_sound_symbol(self):
        for relative in [
            "Console/Features/Chats/SpyderChatTerminalView.swift",
            "Console/Features/Chats/ChatDetailView.swift",
        ]:
            code = (ROOT / relative).read_text()
            self.assertNotIn("SpyderSonicPlayer", code)
            self.assertIn("UINotificationFeedbackGenerator().notificationOccurred(.success)", code)

    def test_terminal_package_remains_linked(self):
        spec = (ROOT / "project.yml").read_text()
        self.assertIn("path: Packages/SpyderTerminalKit", spec)
        self.assertIn("product: SpyderTerminalKit", spec)

if __name__ == "__main__":
    unittest.main()
