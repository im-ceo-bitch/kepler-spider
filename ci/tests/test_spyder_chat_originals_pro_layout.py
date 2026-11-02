"""Source-level invariants for Spyder Pro Chat + Originals 01.

The iOS build and real device rendering are separate gates. This test deliberately
checks integration boundaries which have repeatedly regressed during ZIP overlays.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def src(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


def test_native_background_not_downgraded_to_old_2d_wallpaper():
    detail = src("Console/Features/Chats/ChatDetailView.swift")
    assert "SpyderLayeredChatBackdrop(appearance: appearance" in detail
    assert "onEntryHandled: { spiderEntryConsumed = true }" in detail
    assert ".ignoresSafeArea()" in detail
    assert ".toolbarBackground(.hidden, for: .navigationBar)" in detail


def test_composer_is_keyboard_aware_and_identity_selection_remains_accessible():
    detail = src("Console/Features/Chats/ChatDetailView.swift")
    assert "@FocusState private var composerFocused" in detail
    assert 'Label("Писать как: " + visiblePersonaName' in detail
    assert "if nextPersonaID != nil || changingPersona" in detail
    assert 'Label("Открыть терминал", systemImage: "terminal")' in detail
    assert 'Image(systemName: "circle.hexagongrid")' in detail
    assert '.ignoresSafeArea(edges: .bottom)' in detail
    assert "await chat.sendNextMessage(to: contact.id, text: content, personaID: persona)" in detail


def test_terminal_picker_does_not_use_vertical_space_in_chat():
    terminal = src("Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/TerminalChatShell.swift")
    assert 'Image(systemName: selection == .chat ? "terminal" : "bubble.left")' in terminal
    assert '.accessibilityIdentifier("spyder.chat.terminalToggle")' in terminal
    assert "if !showsChatSwitch {" in terminal
    assert "chatContent()" in terminal
    assert "TerminalExecutionGate" in terminal


def test_originals_payload_is_versioned_and_sent_encrypted_without_draft_loss():
    detail = src("Console/Features/Chats/ChatDetailView.swift")
    originals = src("Console/Features/Chats/SpyderOriginals.swift")
    service = src("Console/ChatLive/SpyderChatService.swift")
    assert 'static let prefix = "spyder:originals:v1:"' in originals
    assert 'case watcher, blink, threat, webDrop, crawl, phantom, webCast, retreat' in originals
    assert "SCNView(frame: .zero)" in originals
    assert "SpyderOriginal.decode(message.text)" in detail
    assert 'transmit(original.payload, clearDraft: false)' in detail
    assert 'if clearDraft && draft.trimmingCharacters(in: .whitespacesAndNewlines) == content' in detail
    assert 'await chat.sendMessage(to: contact.id, text: content)' in detail
    assert 'SpyderOriginal.decode(text)' in service


def test_profile_navigation_read_receipts_and_per_peer_appearance_preserved():
    detail = src("Console/Features/Chats/ChatDetailView.swift")
    session = src("Console/Features/Chats/SpyderConversationSession.swift")
    assert "SpyderChatAppearanceStore.load(peer: contact.id, persona: chat.activePersonaID)" in detail
    assert "SpyderReadViewport.visibleIDs" in detail
    assert "await chat.markRead(peer: contact.id, visibleIDs: ids)" in detail
    assert "SpyderReceiptMark" in detail
    assert "SpyderContactProfilePage(contact: contact" in session
    assert ".navigationBarBackButtonHidden(true)" not in detail
