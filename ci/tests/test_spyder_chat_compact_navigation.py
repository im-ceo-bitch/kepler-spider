"""Compact chat layout and native interactive Back regression guard."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

class CompactChatNavigationTests(unittest.TestCase):
    def test_system_back_gesture_preserved(self):
        chat = read("Console/Features/Chats/ChatDetailView.swift")
        root = read("Console/WalletRootView.swift")
        self.assertIn('ToolbarItem(placement: .principal)', chat)
        self.assertIn('Text(contact.name)', chat)
        self.assertNotIn('.navigationBarBackButtonHidden(true)', chat)
        self.assertNotIn('DragGesture()', chat)
        self.assertIn('NavigationStack(path: $networkPath)', root)
        self.assertIn('.toolbar(.visible, for: .navigationBar)', root)

    def test_compact_title_is_a_profile_link(self):
        chat = read("Console/Features/Chats/ChatDetailView.swift")
        self.assertIn('Button(action: onOpenContact)', chat)
        self.assertIn('Text(contact.name)', chat)
        self.assertIn('SpyderProfileAvatarView(motion: peerAvatar?', chat)  # native procedural avatar protocol
        self.assertNotIn('private var header: some View', chat)
        self.assertNotIn('pickerStyle(.segmented)', chat)

    def test_terminal_access_and_cryptography_are_preserved(self):
        chat = read("Console/Features/Chats/ChatDetailView.swift")
        terminal = read("Console/Features/Chats/SpyderChatTerminalView.swift")
        self.assertNotIn('SpyderChatTerminalView(', chat)
        self.assertIn('SpyderChatPaymentView(', chat)
        self.assertIn('Button(action: onReturnToChat)', terminal)
        self.assertIn('await chat.sendMessage(to: contact.id, text: text)', chat)
        self.assertIn('await chat.loadMessages(peer: contact.id)', chat)
        self.assertNotIn('SpyderLayeredChatBackdrop(', chat)

if __name__ == '__main__':
    unittest.main()
