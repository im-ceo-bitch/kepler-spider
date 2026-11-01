"""Guard identity, message and avatar separation in Persona v1 (without claiming Ghost anonymity)."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
def source(path):return (ROOT/path).read_text(encoding='utf-8')

class PersonaV1Safety(unittest.TestCase):
    def test_never_replace_legacy_identity(self):
        s=source('Console/ChatLive/SpyderChatService.swift')
        self.assertIn('static let account = "device-identity"',s)
        self.assertIn('let original = try? JSONDecoder().decode(SpyderChatIdentity.self',s)
        self.assertIn('SpyderMessageCrypto.bindLegacyPersona(original.id)',s)
        self.assertIn('id == primaryID ? SpyderChatKeychain.account : "persona:" + id',s)
        self.assertIn('clearDecryptedCache()',s)
        self.assertIn('resetPersonaCaches()',s)
        self.assertIn('guard own.id == identity?.id',s)

    def test_crypto_keys_are_persona_scoped(self):
        crypto=source('Console/Security/SpyderMessageCrypto.swift')
        service=source('Console/ChatLive/SpyderChatService.swift')
        self.assertIn('"legacy-persona-owner"',crypto)
        self.assertIn('"persona-keys:" + id',crypto)
        self.assertIn('loadOrCreate(personaID: personaID)',crypto)
        self.assertIn('personaID: own.id',service)
        self.assertIn('personaID: id',service)
        self.assertIn('kind: "private"',service)
        self.assertIn('personaKind != "private"',service)

    def test_contact_avatar_is_native_and_chat_navigation_kept(self):
        home=source('Console/Features/Chats/ChatsHomeView.swift')
        detail=source('Console/Features/Chats/ChatDetailView.swift')
        contact=source('Console/Features/Chats/SpyderContactProfilePage.swift')
        self.assertIn('person.avatar?.motion',home)
        self.assertIn('onOpenActivity: onOpenActivity',detail)
        self.assertIn('SpyderProfileAvatarView',contact)
        self.assertIn('peer?.bio',contact)
        self.assertIn('seed: peer?.avatar?.seed',contact)

    def test_persona_picker_tells_truth_about_privacy(self):
        view=source('Console/Features/Settings/SpyderPersonasView.swift')
        self.assertIn('НЕ гарантия анонимности перед сервером',view)
        self.assertIn('createPrivatePersona',view)
        self.assertIn('activatePersona',view)

if __name__ == '__main__': unittest.main()
