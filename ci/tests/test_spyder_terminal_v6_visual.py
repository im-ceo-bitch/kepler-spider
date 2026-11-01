from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'Packages/SpyderTerminalKit/Sources/SpyderTerminalKit'


def source(name):
    return (SRC / name).read_text(encoding='utf-8')


def test_light_and_older_modes_available():
    assert 'case system, light, dark, oled' in source('TerminalModels.swift')
    assert 'TerminalAppearance.light' in source('TerminalViews.swift')


def test_terminal_color_scheme_is_not_hardwired_dark():
    shell = source('TerminalChatShell.swift')
    assert 'settings.appearance == .system ? systemColorScheme : .dark' not in shell
    assert 'terminalScheme' in shell
    assert 'palette.background' in shell


def test_live_color_editor_does_not_run_scripts():
    editor = source('TerminalSyntaxEditor.swift')
    assert 'markedTextRange == nil' in editor
    assert 'selectedRange' in editor
    assert 'UITextViewDelegate' in editor
    assert 'eval(' not in editor


def test_global_and_chat_use_same_terminal_and_palette():
    shell = source('TerminalChatShell.swift')
    assert 'TerminalSyntaxText.render(entry.command' in shell
    assert 'SpyderTerminalInputView(settings:' in shell
    assert 'TerminalExecutionGate' in shell
