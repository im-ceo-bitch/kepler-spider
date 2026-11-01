from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[2]

def test_terminal_is_namespaced():
    assert (ROOT/'Packages/SpyderTerminalKit/Package.swift').exists()
    assert not (ROOT/'Sources/SpyderTerminalKit').exists()

def test_terminal_dependency_exists():
    project=(ROOT/'project.yml').read_text()
    assert 'path: Packages/SpyderTerminalKit' in project
    assert 'product: SpyderTerminalKit' in project

def test_chat_is_wrapped_without_cryptography_changes():
    root=(ROOT/'Console/WalletRootView.swift').read_text()
    bridge=(ROOT/'Console/Features/Chats/SpyderTerminalChatContainer.swift').read_text()
    assert 'SpyderTerminalChatContainer(contact: contact' in root
    assert 'ChatDetailView(contact: contact' in bridge
    assert 'TerminalActionContext(conversationID: contact.id)' in bridge
    assert 'wallet.send' not in bridge
    assert 'chat.broadcast' not in bridge
