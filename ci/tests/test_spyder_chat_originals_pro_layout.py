"""Minimal wallet-chat product boundaries. Source checks do not replace Xcode/device tests."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def src(path):return (ROOT/path).read_text()

def test_chat_has_no_runtime_wallpaper_or_sticker_renderer():
    detail=src('Console/Features/Chats/ChatDetailView.swift')
    for retired in ('SpyderLayeredChatBackdrop(', 'SpyderOriginalView(', 'SpyderOriginalsPicker(', 'SpyderChatAppearanceStore.load('):
        assert retired not in detail
    assert '.background(Color.white.ignoresSafeArea())' in detail

def test_composer_is_keyboard_aware_and_payment_action_is_accessible():
    detail=src('Console/Features/Chats/ChatDetailView.swift')
    assert '@FocusState private var composerFocused' in detail
    assert '.lineLimit(1...5)' in detail
    assert 'spyder.chat.transfer' in detail
    assert 'selectChatPersona(id, peer: contact)' in detail
    assert '.ignoresSafeArea(edges: .bottom)' not in detail

def test_terminal_and_scenekit_are_excluded_from_app_sources():
    project=src('project.yml')
    assert 'excludes:' in project
    assert 'Features/Chats/SpyderOriginals.swift' in project
    assert 'Features/Chats/SpyderChatTerminalView.swift' in project
    assert 'product: SpyderTerminalKit' not in project
    session=src('Console/Features/Chats/SpyderConversationSession.swift')
    assert 'SpyderTerminalChatContainer(' not in session
    assert 'ChatDetailView(contact: contact' in session

def test_message_path_remains_signed_and_legacy_stickers_are_text_only():
    detail=src('Console/Features/Chats/ChatDetailView.swift')
    service=src('Console/ChatLive/SpyderChatService.swift')
    protocol=src('Console/Features/Chats/SpyderChatPayments.swift')
    assert 'await chat.sendMessage(to: contact.id, text: text)' in detail
    assert 'SpyderMessageCrypto.seal(clean' in service
    assert 'SpyderPaymentEnvelope.preview(text)' in service
    assert 'spyder:originals:' in protocol
    assert 'Стикер скрыт' in protocol

def test_profile_navigation_and_real_read_receipts_preserved():
    detail=src('Console/Features/Chats/ChatDetailView.swift')
    session=src('Console/Features/Chats/SpyderConversationSession.swift')
    assert 'SpyderReadViewport.visibleIDs' in detail
    assert 'await chat.markRead(peer: contact.id, visibleIDs: ids)' in detail
    assert 'SpyderReceiptMark' in detail
    assert 'SpyderContactProfilePage(contact: contact' in session
    assert '.navigationBarBackButtonHidden(true)' not in detail
