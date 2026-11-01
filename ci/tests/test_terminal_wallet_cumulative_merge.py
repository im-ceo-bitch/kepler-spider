"""Regression checks for merging Terminal v1 with Wallet Control v2.

Static checks; these do not replace an Xcode compilation or device tests.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def read(relative):
    return (ROOT / relative).read_text(encoding='utf-8')

class TerminalWalletCumulativeMergeTests(unittest.TestCase):
    def test_control_center_and_terminal_routing_coexist(self):
        root = read('Console/WalletRootView.swift')
        self.assertIn('WalletControlCenterView(', root)
        self.assertIn('onControlCenter:', root)
        self.assertIn('case .security:', root)
        self.assertIn('WalletSecurityCenterView()', root)
        self.assertIn('case .addressBook:', root)
        self.assertIn('WalletAddressBookView()', root)
        self.assertIn('onOpenActivity:', root)
        self.assertIn('SpyderTerminalChatContainer(contact: contact', root)
        self.assertIn('ChatDetailView(contact: contact', read('Console/Features/Chats/SpyderTerminalChatContainer.swift'))
        self.assertIn('WalletSettingsView()', root)
        self.assertIn('openChatAfterNotificationIfNeeded()', root)
        self.assertIn('.spyderChatOpenRequested', root)

    def test_terminal_package_in_xcodegen(self):
        project = read('project.yml')
        self.assertIn('path: Packages/SpyderTerminalKit', project)
        self.assertIn('product: SpyderTerminalKit', project)
        self.assertIn('product: WalletCore', project)

    def test_terminal_ui_available_in_chats_and_settings(self):
        self.assertIn('SpyderChatTerminalSwitchView(', read('Console/Features/Chats/SpyderTerminalChatContainer.swift'))
        self.assertIn('SpyderTerminalSettingsScreen()', read('Console/Features/Settings/WalletSettingsView.swift'))
        self.assertIn('struct SpyderChatTerminalView', read('Console/Features/Chats/SpyderChatTerminalView.swift'))

    def test_market_and_chat_preserved(self):
        self.assertIn('WalletCatalogSection(catalog: catalog)', read('Console/Features/Wallet/WalletHomeView.swift'))
        self.assertIn('WalletLiveMarket', read('Console/WalletCore/WalletLiveMarket.swift'))
        self.assertIn('class SpyderChatStore', read('Console/ChatLive/SpyderChatService.swift'))
        self.assertTrue((ROOT / 'server/src/chat.mjs').exists())

if __name__ == '__main__':
    unittest.main()
