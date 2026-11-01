"""Term v5: regressions on actual integration, no synthetic host / fake success."""
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
def get(filename): return (ROOT/filename).read_text()

class TerminalV5Regressions(unittest.TestCase):
    def test_bilingual_command_parity(self):
        ru,en=(json.loads(get('Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/Resources/commands.'+loc+'.json')) for loc in ('ru','en'))
        self.assertEqual(len(ru),35)
        self.assertEqual({x['id']:x['risk'] for x in ru},{x['id']:x['risk'] for x in en})
        for catalog in (ru,en):
            ids={c['id'] for c in catalog}
            self.assertTrue({'terminal.language.set','terminal.accent.set','terminal.appearance.set','terminal.autocomplete.set','terminal.font.set'}.issubset(ids))
            self.assertEqual(next(x for x in catalog if x['id']=='wallet.send')['risk'],'sensitive')
            self.assertEqual(next(x for x in catalog if x['id']=='chat.broadcast')['risk'],'sensitive')

    def test_existing_profile_service_used(self):
        service=get('Console/ChatLive/SpyderChatService.swift')
        self.assertIn('func updateDisplayName(',service)
        for name in ('SpyderTerminalChatContainer.swift','SpyderGlobalTerminalView.swift'):
            source=get('Console/Features/Chats/'+name)
            self.assertIn('host.register("profile.name.set")',source)
            self.assertIn('await chat.updateDisplayName(name)',source)
            self.assertIn('guard await chat.updateDisplayName(name) else',source)

    def test_push_handlers_do_not_claim_server_delivery(self):
        for name in ('SpyderTerminalChatContainer.swift','SpyderGlobalTerminalView.swift'):
            source=get('Console/Features/Chats/'+name)
            self.assertIn('host.register("settings.notifications.enable")',source)
            self.assertIn('host.register("settings.notifications.disable")',source)
            self.assertIn('await chat.enablePush()',source)
            self.assertIn('await chat.disablePush()',source)
            self.assertIn('registration may still be pending',source)
            self.assertNotIn('host.register("wallet.send"',source)
            self.assertNotIn('host.register("chat.broadcast"',source)
            self.assertNotIn('host.register("profile.bio.set"',source)
            self.assertNotIn('host.register("chat.pin"',source)

    def test_parser_filters_suggestions_and_local_actions(self):
        shell=get('Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/TerminalChatShell.swift')
        engine=get('Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/TerminalEngine.swift')
        self.assertIn('union(TerminalPreferenceCommands.actionIDs)',shell)
        self.assertIn('TerminalPreferenceCommands.apply(match, settings: &settings)',shell)
        self.assertIn('availableCommands: { supportedCommands() }',shell)
        self.assertIn('availableCommandIDs: availableCommands()',get('Packages/SpyderTerminalKit/Sources/SpyderTerminalKit/TerminalViews.swift'))
        self.assertIn('Self.argumentChoices(',engine)

if __name__=='__main__':unittest.main()
