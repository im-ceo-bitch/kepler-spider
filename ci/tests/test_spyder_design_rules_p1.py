"""P1 release guards: design rules must survive UI refactoring."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class DesignRulesP1Tests(unittest.TestCase):
    def test_onboarding_uses_acknowledgement_buttons_not_toggles(self):
        view = source("Console/Features/Onboarding/WalletOnboardingView.swift")
        self.assertIn("Button { confirmOffline.toggle() }", view)
        self.assertIn("Button { testPhraseOnly.toggle() }", view)
        self.assertNotIn('Toggle("Я записал', view)
        self.assertNotIn('Toggle("Это фраза', view)
        self.assertIn(".disabled(!confirmOffline)", view)
        self.assertIn(".disabled(!testPhraseOnly ||", view)
        self.assertIn("private var isVerified: Bool", view)

    def test_appearance_has_no_animated_gallery(self):
        view = source("Console/Features/Chats/SpyderChatAppearanceSettingsView.swift")
        self.assertNotIn("SpyderNativeSpiderPicker(", view)
        self.assertNotIn("SpyderChatWallpaperView(", view)
        self.assertNotIn("Slider(", view)
        self.assertIn("clean.spider.enabled = false", view)
        self.assertIn("SpyderChatAppearanceStore.save(appearance", view)

    def test_unused_legacy_spider_editor_is_not_rendered(self):
        view = source("Console/Features/Chats/SpyderNativeSpiderPicker.swift")
        self.assertIn("EmptyView()", view)
        self.assertNotIn("SpyderVectorArtworkView(", view)
        self.assertNotIn("SpyderNativeBackdropView(", view)

    def test_cloud_backup_has_explicit_consent_and_plain_language(self):
        view = source("Console/Features/Settings/WalletSettingsView.swift")
        self.assertIn("$confirmingCloudBackup", view)
        self.assertIn('Button("Отмена", role: .cancel)', view)
        self.assertIn("обычные облачные файлы", view)
        self.assertIn("backupCloudBusy = true", view)
        self.assertIn("WalletICloudRecovery.saveWithConsent", view)

    def test_themes_do_not_write_unapplied_preferences(self):
        for path in (
            "Console/Features/Chats/SpyderTerminalChatContainer.swift",
            "Console/Features/Chats/SpyderGlobalTerminalView.swift",
            "Console/Features/Chats/SpyderChatTerminalView.swift",
        ):
            view = source(path)
            self.assertIn('"settings.theme.set"', view)
            self.assertIn("настройки не изменены", view.lower(), path)
            self.assertNotIn('UserDefaults.standard.set(appearance.rawValue, forKey: "spyder.wallet.appearance")', view)
            self.assertNotIn('walletAppearance = WalletAppearance.dark.rawValue', view)

    def test_legacy_command_catalog_does_not_promise_old_appearance(self):
        import json
        for lang in ("ru", "en"):
            commands = json.loads(source(f"Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/Resources/commands.{lang}.json"))
            theme = next(x for x in commands if x["id"] == "settings.theme.set")
            chat_theme = next(x for x in commands if x["id"] == "chat.theme.set")
            self.assertIn("not available" if lang == "en" else "недоступ", theme["summary"])
            self.assertIn("disabled" if lang == "en" else "отключен", chat_theme["summary"])

    def test_send_shortcuts_have_minimum_hit_height(self):
        view = source("Console/Features/Wallet/WalletSendFlowView.swift")
        start = view.index('Label("Вставить", systemImage:')
        end = view.index('if !recipient.isEmpty && !recipientValid', start)
        actions = view[start:end]
        self.assertGreaterEqual(actions.count(".frame(minHeight: 44)"), 3)
        self.assertIn('.accessibilityHint(', actions)


if __name__ == "__main__":
    unittest.main()
