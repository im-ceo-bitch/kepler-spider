#!/usr/bin/env python3
"""Code-level smoke checks for Stage 2 architecture. Not a UI/runtime test."""
from pathlib import Path

r = Path(__file__).resolve().parents[1]
def read(file):
    return (r / file).read_text(encoding='utf-8')

chats = read('Console/Features/Chats/ChatsHomeView.swift')
invite = read('Console/Features/Chats/SpyderInvitePage.swift')
identity = read('Console/Features/Settings/SpyderIdentityHubView.swift')
wallet = read('Console/Features/Wallet/WalletHomeView.swift')
profile = read('Console/Features/Wallet/SpyderWalletProfilePage.swift')
settings = read('Console/Features/Settings/WalletSettingsView.swift')
detail = read('Console/Features/Chats/ChatDetailView.swift')
root = read('Console/WalletRootView.swift')

checks = {
    'bottom navigation remains Wallet/Chats only': 'tabButton(.wallet' in root and 'tabButton(.chats' in root,
    'two navigation stacks retain independent histories': '@State private var walletPath:' in root and '@State private var networkPath:' in root,
    'inbox explicitly exposes profile': 'Button(action: onProfile)' in chats and 'accessibilityLabel("Мой Spyder ID и настройки")' in chats,
    'inbox explicitly exposes compose': 'Button(action: onAdd)' in chats and 'accessibilityLabel("Новый чат")' in chats,
    'inbox does not prompt for username': 'TextField("Создать @username"' not in chats,
    'inbox does not show persona carousel': 'identityCarousel' not in chats and 'showPersonas' not in chats,
    'inbox search and contacts retained': 'Поиск переписок' in chats and 'Контакты' in chats and 'contactsSection' in chats,
    'archive still reachable through filter': 'archived.toggle()' in chats and 'Фильтры переписок' in chats,
    'chat swipe archive/pin/block behavior retained': '"unarchive" : "archive"' in chats and '"unpin" : "pin"' in chats and 'chat.block(person.id)' in chats,
    'new chat begins with user lookup': invite.index('Text("Найти человека")') < invite.index('Text("Другие способы")'),
    'touch direct option from new chat': 'Text("Spyder Touch")' in invite and 'showingTouch = true' in invite,
    'code invitation is opened on deep link': 'showCodeEntry = true' in invite and 'chat.pendingInviteCode' in invite,
    'QR from photos preserves validation': 'PhotosPicker(selection: $photo' in invite and 'Set(codes).count == 1' in invite,
    'own invite QR and code are secondary': 'DisclosureGroup(isExpanded: $showMyInvite)' in invite and 'showMyInvite = false' in invite,
    'privacy no longer configured from new chat': 'Toggle("Приглашения только' not in invite and 'setLimitUnknownContacts' not in invite,
    'privacy is editable in Spyder ID': 'Text("Приватность и приглашения")' in identity and 'chat.setLimitUnknownContacts(enabled)' in identity,
    'privacy state loaded for profile': 'await chat.loadInviteSettings()' in identity,
    'technical networking settings collapsed': 'DisclosureGroup(isExpanded: $showingTechnicalSettings)' in identity,
    'wallet always starts as portfolio': '@State private var selectedSection = WalletHomeSection.assets.rawValue' in wallet,
    'market has dedicated entry and back': 'private var marketEntry:' in wallet and 'private var marketNavigationHeader:' in wallet,
    'market never merged into balances view': wallet.index('if selectedSection == WalletHomeSection.cryptocurrencies.rawValue') < wallet.index('portfolioCard\n                        quickActions'),
    'market and wallet restore scroll top': '.id(selectedSection)' in wallet,
    'wallet account selection retained': 'onAction(.accounts)' in wallet and 'label: "Профиль", action: onControlCenter' in wallet,
    'wallet addresses opt-in details': 'DisclosureGroup(isExpanded: $showAddresses)' in profile and 'addressesContent' in profile,
    'privacy toggle moved to persistent wallet settings': 'Toggle(isOn: $privacyHidden)' in settings and 'Toggle(isOn: $privacyHidden)' not in profile,
    'chat plus menu no longer duplicates transfer': 'Menu {\n                Button { openPayment()' not in detail,
    'primary chat transfer action remains': 'accessibilityIdentifier("spyder.chat.transfer")' in detail,
}

for title, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ': ' + title)
if not all(checks.values()):
    raise SystemExit('Stage 2 UX static checks failed')
print(f'Passed {len(checks)} stage-two static UX checks')
