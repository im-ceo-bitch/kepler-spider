"""Wallet-only regression checks. Full iOS typecheck happens on macOS build-only."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(name): return (ROOT / name).read_text(encoding='utf-8')


class WalletAddressBookRegression(unittest.TestCase):
    def test_keychain_and_isolation(self):
        source = read('Console/WalletCore/WalletAddressBook.swift')
        self.assertIn('kSecAttrAccessibleWhenUnlockedThisDeviceOnly', source)
        self.assertIn('kSecAttrSynchronizable as String: false', source)
        self.assertIn('let q = query(walletID)', source)
        self.assertIn('func selectWallet(_ id: String)', source)
        self.assertIn('entries = try Self.load(walletID)', source)
        self.assertIn('guard errorMessage == nil else', source)
        self.assertNotIn('WalletVault.revealForBackup', source)
        self.assertNotIn('URLSession', source)

    def test_ui_flow_connected(self):
        app = read('Console/ConsoleApp.swift')
        self.assertIn('@StateObject private var addressBook = WalletAddressBookStore()', app)
        self.assertIn('.environmentObject(addressBook)', app)
        self.assertIn('addressBook.selectWallet(id)', app)
        root = read('Console/WalletRootView.swift')
        self.assertIn('case .addressBook:', root)
        self.assertIn('WalletAddressBookView()', root)
        center = read('Console/Features/Wallet/WalletControlCenterView.swift')
        self.assertIn('onAddressBook', center)
        send = read('Console/Features/Wallet/WalletSendFlowView.swift')
        self.assertIn('WalletAddressBookView(onSelect:', send)
        self.assertIn('WalletAddressBookAddView(chain: selected, address: normalizedRecipient)', send)
        self.assertIn('WalletAddressValidator.check(normalizedRecipient, for: selected)', send)
        self.assertIn('showUnavailable = true', send) # still no broadcast
        self.assertNotIn('eth_sendRawTransaction', send)

    def test_validation_is_not_a_fake_authorization(self):
        source = read('Console/WalletCore/WalletAddressValidator.swift')
        self.assertIn('0x2bc830a3', source)
        self.assertIn('let expected = version == 0 ? 1', source)
        self.assertIn('decoded.count == 32', source)
        self.assertIn('EIP-55 checksums require Keccak-256', source)
        self.assertNotIn('return .valid // any', source)

    def test_activity_filters_are_read_only(self):
        source = read('Console/Features/Wallet/WalletHomeView.swift')
        self.assertIn('@State private var chainFilter = "all"', source)
        self.assertIn('@State private var statusFilter = "all"', source)
        self.assertIn('private func visibleEntries(_ chain: SpyderChain)', source)
        self.assertIn('WalletChainActivity.State.confirmed.rawValue', source)

    def test_localization(self):
        for lang in ('ru', 'en'):
            source = read(f'Console/Resources/{lang}.lproj/Localizable.strings')
            for key in ('Адресная книга', 'Новый получатель', 'Проверенные публичные адреса по сетям', 'Фильтры'):
                self.assertIn('"' + key + '" = ', source)

if __name__ == '__main__': unittest.main()
