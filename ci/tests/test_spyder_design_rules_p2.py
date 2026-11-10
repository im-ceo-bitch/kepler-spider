"""P2 design-system guards: accessibility, hierarchy and touch geometry.

These tests inspect source structure. They do not replace SwiftUI layout checks on iOS.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]

def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")

class DesignRulesP2Tests(unittest.TestCase):
    PRIORITY_UI = (
        "Console/Design/WalletTheme.swift",
        "Console/Design/MotionKit/SpyderMotionSettingsView.swift",
        "Console/Features/Wallet/WalletCatalogViews.swift",
        "Console/Features/Wallet/WalletHomeView.swift",
        "Console/Features/Wallet/WalletTransferView.swift",
        "Console/Features/Wallet/WalletLiveStageView.swift",
        "Console/Features/Wallet/WalletAddressBookView.swift",
        "Console/Features/Wallet/SpyderWalletProfilePage.swift",
        "Console/Features/Chats/ChatsHomeView.swift",
        "Console/Features/Settings/SpyderIdentityHubView.swift",
        "Console/Features/Onboarding/WalletOnboardingView.swift",
    )

    def test_priority_screens_avoid_fixed_micro_fonts(self):
        for file in self.PRIORITY_UI:
            with self.subTest(file=file):
                content = read(file)
                for match in re.finditer(r"\.font\(\.system\(size:\s*(\d+)", content):
                    self.assertGreaterEqual(int(match.group(1)), 14, file)

    def test_dynamic_monetary_amount_and_privacy_still_work(self):
        content = read("Console/Features/Wallet/WalletHomeView.swift")
        self.assertIn("@ScaledMetric(relativeTo: .largeTitle) private var balanceSize", content)
        self.assertIn(".privacySensitive()", content)
        self.assertIn(".monospacedDigit()", content)
        self.assertIn('Text(privacyHidden ? "••••••"', content)

    def test_market_filters_can_scroll_without_hiding_refresh(self):
        content = read("Console/Features/Wallet/WalletCatalogViews.swift")
        start = content.index("// Scroll filters when Dynamic Type grows")
        end = content.index('.accessibilityLabel("Обновить котировки")', start)
        segment = content[start:end]
        self.assertIn('ScrollView(.horizontal, showsIndicators: false)', segment)
        self.assertIn('Menu {', segment)
        self.assertIn('favoritesOnly.toggle()', segment)
        self.assertIn('Button { Task { await catalog.refresh(force: true) } }', segment)
        self.assertIn('.accessibilityValue(order.title)', segment)
        self.assertIn('.accessibilityValue(favoritesOnly ? "Включено" : "Выключено")', segment)

    def test_clear_search_meets_touch_target_rule(self):
        content = read("Console/Features/Wallet/WalletCatalogViews.swift")
        start = content.index('if !query.isEmpty {')
        self.assertIn('.frame(width: 44, height: 44)', content[start:start+420])
        self.assertIn('accessibilityLabel("Очистить поиск")', content[start:start+420])

    def test_market_rows_prioritize_price_at_accessibility_sizes(self):
        content = read("Console/Features/Wallet/WalletCatalogViews.swift")
        self.assertIn('@Environment(\\.dynamicTypeSize) private var dynamicTypeSize', content)
        self.assertIn('!dynamicTypeSize.isAccessibilitySize && coin.sparkline7d.count >= 2', content)
        self.assertIn('.lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)', content)

    def test_chart_periods_have_accessible_hit_geometry(self):
        catalog = read("Console/Features/Wallet/WalletCatalogViews.swift")
        live = read("Console/Features/Wallet/WalletLiveStageView.swift")
        self.assertIn('.frame(minWidth: 54, minHeight: 44)', catalog)
        self.assertIn('accessibilityLabel("Период графика: " + option.label)', catalog)
        self.assertIn('.frame(minHeight: 44)', live)
        self.assertIn('accessibilityLabel("Период графика: " + option.label)', live)

    def test_disclosure_reduces_technical_visual_noise(self):
        catalog = read("Console/Features/Wallet/WalletCatalogViews.swift")
        self.assertIn('DisclosureGroup("Источники цен и ограничения")', catalog)
        self.assertIn('не означает поддержку хранения', catalog)
        self.assertIn('Цены ориентировочные', catalog)

    def test_no_fake_theme_control_inside_live_chart(self):
        live = read("Console/Features/Wallet/WalletLiveStageView.swift")
        self.assertNotIn('ForEach(WalletAppearance.allCases)', live)
        self.assertNotIn('appearance = option.rawValue', live)
        self.assertIn('Button { dismiss() } label:', live)

    def test_history_action_and_unread_count_remain_accessible(self):
        home = read("Console/Features/Wallet/WalletHomeView.swift")
        chat = read("Console/Features/Chats/ChatsHomeView.swift")
        self.assertIn('accessibilityLabel("Открыть всю историю операций")', home)
        self.assertIn('.frame(minWidth: 44, minHeight: 44)', home)
        self.assertIn('accessibilityLabel("Непрочитанных сообщений: " + String(item.unread_count))', chat)
        self.assertIn('animate: motionEnabled && !reduceMotion', chat)

if __name__ == "__main__":
    unittest.main()
