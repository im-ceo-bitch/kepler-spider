"""Wallet Control Center safety and integration guards; full Xcode build still required."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
def src(p): return (ROOT/p).read_text(encoding='utf-8')
class ControlCenterTests(unittest.TestCase):
    def test_wallet_and_chat_use_distinct_credentials(self):
        panel=src('Console/Features/Wallet/SpyderWalletProfilePage.swift')
        network=src('Console/Features/Settings/SpyderIdentityHubView.swift')
        assert 'WalletAccess' in panel and 'SpyderChatStore' not in panel
        assert 'WalletVault.revealForBackup' not in panel
        assert 'spyder.chat.push.open.pending' not in panel
        assert 'chat.myUsername' in network and 'access.activeAccountName' in panel
        self.assertNotIn('WalletVault.save(',panel)
    def test_wallet_profile_has_discoverable_button_and_chat_has_no_edge_gesture(self):
        # Stage 2 replaces the undiscoverable edge swipe with an explicit button.
        home=src('Console/Features/Wallet/WalletHomeView.swift')
        self.assertIn('headerButton("person.crop.circle", label: "Профиль", action: onControlCenter)', home)
        self.assertIn('.frame(width: 44, height: 44)', home)
        self.assertIn('WalletCatalogSection(catalog: catalog)', home)
        self.assertNotIn('DragGesture', home)
        self.assertNotIn('DragGesture', src('Console/Features/Chats/ChatsHomeView.swift'))
    def test_root_keeps_chat_navigation_and_push(self):
        root=src('Console/WalletRootView.swift')
        assert 'openChatAfterNotificationIfNeeded()' in root
        assert 'selectedTab = .chats' in root
        assert '.spyderChatOpenRequested' in root
        assert 'SpyderWalletProfilePage(' in root
        assert 'NavigationStack(path: $walletPath)' in root
        assert 'NavigationStack(path: $networkPath)' in root
        assert '.fullScreenCover(isPresented: $showControlCenter)' not in root
        assert 'case .security:' in root
        assert 'WalletSendFlowView(preselected: sendChain)' in root
    def test_security_does_not_claim_cloud_copy_was_verified(self):
        v=src('Console/Features/Wallet/WalletSecurityCenterView.swift')
        assert 'WalletVault.exists(id: access.activeWalletID)' in v
        assert 'WalletICloudRecovery.exists()' in v
        assert 'Это не проверяет' in v
        assert 'access.lock()' in v
        assert 'WalletSettingsView()' in v
    def test_project_auto_discovers_new_source_and_localization(self):
        assert 'path: Console' in src('project.yml')
        for locale in ('ru','en'):
            strings=src(f'Console/Resources/{locale}.lproj/Localizable.strings')
            for key in ['Мои кошельки','Скрывать балансы','Заблокировать кошелёк','Ключи Wallet и Network защищены отдельно. Управление ими объединено только в интерфейсе.']:
                self.assertIn(f'"{key}" =',strings)
if __name__ == '__main__': unittest.main()
