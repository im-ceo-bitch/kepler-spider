#!/usr/bin/env python3
"""Static regression gates for Stage-1 UI contracts; not a simulator UI test."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
def source(rel):
    return (root / rel).read_text(encoding="utf-8")

ui = source("Console/Design/WalletTheme.swift")
home = source("Console/Features/Wallet/WalletHomeView.swift")
receive = source("Console/Features/Wallet/WalletTransferView.swift")
send = source("Console/Features/Wallet/WalletSendFlowView.swift")
chats = source("Console/Features/Chats/ChatsHomeView.swift")
invite = source("Console/Features/Chats/SpyderInvitePage.swift")
payment = source("Console/Features/Chats/SpyderChatPaymentView.swift")
catalog = source("Console/Features/Wallet/WalletCatalogViews.swift")

checks = {
    "action style has four kinds": "case primary, secondary, tertiary, destructive" in ui,
    "primary touch height >= 52 pt": "kind == .tertiary ? 44 : 52" in ui,
    "legacy button uses capsule": ".background(WalletTheme.accent, in: Capsule())" in ui,
    "market and wallet choice copy": 'NSLocalizedString("Портфель"' in home and 'NSLocalizedString("Рынок"' in home,
    "no generic send promise on wallet home": 'actionButton("Подготовить перевод"' in home,
    "receive uses explicit acknowledgment": 'Label("Показать адрес и QR"' in receive and 'Toggle("Я проверил сеть' not in receive,
    "receiving asset choice marked selected": ".accessibilityAddTraits(selected == item ? .isSelected : [])" in receive,
    "unsupported send returns to review": '"Вернуться к реквизитам"' in send and 'showUnavailable' not in send,
    "disabled send offers address feedback": '"Адрес не соответствует выбранной сети."' in send,
    "market filter touch targets": 'frame(width: 44, height: 44)' in catalog and catalog.count('frame(minHeight: 44)') >= 2,
    "chat payment uses shared action styles": 'ChatPaymentPrimaryButton' not in payment and 'SpyderActionButtonStyle' in payment,
    "chat filtering isn't a switch": 'Toggle("Показать скрытые"' not in chats and 'SpyderChoiceButtonStyle(selected: showHidden)' in chats,
    "invite connect button has explicit label": '"Подключиться по коду"' in invite,
}
for title, ok in checks.items():
    print(("PASS" if ok else "FAIL") + ": " + title)
if not all(checks.values()):
    raise SystemExit(1)
print(f"Passed {len(checks)} stage-one static UX checks")
