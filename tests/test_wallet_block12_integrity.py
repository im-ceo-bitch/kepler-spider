"""Linux-safe source regression checks. Does not substitute for xcodebuild or on-device QA."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WalletBlock12Integrity(unittest.TestCase):
    def source(self, name: str) -> str:
        return (ROOT / name).read_text(encoding="utf-8")

    def test_legacy_keychain_account_is_migrated_without_seed_export(self):
        source = self.source("Console/Security/WalletVault.swift")
        self.assertIn('id == legacyID ? "bip39-english-mnemonic"', source)
        self.assertIn("kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly", source)
        self.assertIn("static func accountIDs()", source)
        self.assertNotIn("UserDefaults.standard.set(phrase", source)

    def test_icloud_backup_is_explicit_only(self):
        vault = self.source("Console/Security/WalletVault.swift")
        onboarding = self.source("Console/Features/Onboarding/WalletOnboardingView.swift")
        self.assertIn("saveWithConsent", vault)
        self.assertIn("kSecAttrSynchronizable as String: true", vault)
        self.assertIn("kSecAttrAccessibleWhenUnlocked", vault)
        self.assertIn("Button { restoreFromICloud() }", onboarding)
        self.assertIn("Копировать слова (45 секунд)", onboarding)

    def test_multiwallet_cache_isolated(self):
        source = self.source("Console/WalletCore/WalletChains.swift")
        self.assertIn('"spyder.wallet.publicAddresses.v2." + id', source)
        self.assertIn("derivationGeneration", source)
        self.assertIn("WalletVault.revealForBackup(id: id)", source)
        assets = self.source("Console/WalletCore/WalletPublicAssets.swift")
        self.assertIn("refreshGeneration", assets)
        self.assertIn("resetForAccountChange", assets)

    def test_no_unverified_mainnet_broadcast(self):
        source = self.source("Console/Features/Wallet/WalletSendFlowView.swift")
        self.assertIn("Отправка пока недоступна", source)
        self.assertIn("Никогда не вставляйте сюда seed-фразу", source)
        self.assertNotIn("eth_sendRawTransaction", source)
        self.assertNotIn("sendTransaction(", source)

    def test_locale_both_present_and_keys_match(self):
        ru = self.source("Console/Resources/ru.lproj/Localizable.strings")
        en = self.source("Console/Resources/en.lproj/Localizable.strings")
        pattern = r'^"((?:\\.|[^"])*)"\s*=\s*"((?:\\.|[^"])*)";'
        ru_keys = set(re.findall(pattern, ru, re.M))
        en_keys = set(re.findall(pattern, en, re.M))
        self.assertEqual({k for k, _ in ru_keys}, {k for k, _ in en_keys})
        self.assertGreaterEqual(len(ru_keys), 100)


if __name__ == "__main__":
    unittest.main()
