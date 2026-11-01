"""Wallet-only product guards; these do not replace an Xcode/Simulator build."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
HOME = (ROOT / 'Console/Features/Wallet/WalletHomeView.swift').read_text()
DETAILS = (ROOT / 'Console/Features/Wallet/WalletProductViews.swift').read_text()
ROOT_VIEW = (ROOT / 'Console/WalletRootView.swift').read_text()
RECEIVE = (ROOT / 'Console/Features/Wallet/WalletTransferView.swift').read_text()


class WalletPortfolioUIRegressions(unittest.TestCase):
    def test_header_stays_outside_scrolling_content(self):
        body = HOME.split('var body: some View {', 1)[1].split('private func refreshWallet()', 1)[0]
        self.assertRegex(body, r'VStack\(spacing:\s*0\)\s*\{\s*walletHeader')
        self.assertLess(body.index('walletHeader'), body.index('ScrollView(showsIndicators: false)'))
        self.assertIn('.background(WalletTheme.canvas)', body)

    def test_assets_are_live_store_data_not_demo_balances(self):
        self.assertIn('publicAssets.balances[chain]', HOME)
        self.assertIn('publicAssets.prices[chain]', HOME)
        self.assertIn('publicAssets.stablecoins[token.ticker]', HOME)
        self.assertIn('WalletTokenCatalog.ethereumERC20', HOME)
        self.assertIn('guard let balance = publicAssets.balances[chain]', HOME)
        self.assertNotIn('Crypto assets', HOME)

    def test_tokens_have_real_destinations_and_verified_contracts(self):
        self.assertIn('.sheet(item: $selectedToken)', HOME)
        self.assertIn('WalletTokenDetailView(token: token)', HOME)
        self.assertIn('let token: WalletVerifiedToken', DETAILS)
        self.assertIn('Text(token.contract)', DETAILS)
        self.assertIn('WalletReceiveView(preselected: .ethereum)', DETAILS)

    def test_receive_goes_to_ethereum_not_test_devnet(self):
        self.assertIn('WalletReceiveView(preselected: sendChain ?? .ethereum)', ROOT_VIEW)
        self.assertIn('@State private var selected: SpyderChain? = .ethereum', RECEIVE)
        self.assertLess(RECEIVE.index('ForEach(SpyderChain.allCases)'),
                        RECEIVE.index('Button { selected = nil; acknowledge = false; copied = false }'))

    def test_devnet_only_shown_when_configured(self):
        self.assertRegex(HOME, r'if\s+spider\.hasConfiguration\s*\{\s*DisclosureGroup')
        self.assertIn('if spider.hasConfiguration', HOME)


if __name__ == '__main__':
    unittest.main()
