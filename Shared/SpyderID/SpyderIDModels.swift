import Foundation
import CryptoKit
import Security

// Independent device-local vault. Never uses wallet seed material or chat identities.
enum SpyderIDKind: String, Codable, CaseIterable, Identifiable {
    case passwords, documents, notes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .passwords: return sidText("Пароли", "Passwords")
        case .documents: return sidText("Документы", "Documents")
        case .notes: return sidText("Заметки", "Notes")
        }
    }
    var symbol: String {
        switch self {
        case .passwords: return "key.horizontal"
        case .documents: return "doc.text"
        case .notes: return "note.text"
        }
    }
}

struct SpyderIDRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: SpyderIDKind
    var title = ""
    var website = ""
    var username = ""
    var password = ""
    var note = ""
    var fileName: String?
    var fileData: Data?
    var modified = Date()
    var isDraft: Bool? = nil
    var categoryLabel: String? = nil
    var passkey: SpyderIDPasskey? = nil
}

struct SpyderIDPayload: Codable {
    let version: Int
    var records: [SpyderIDRecord]
}

enum SpyderIDFailure: LocalizedError {
    case locked, missingKey, passcode, storage, incompatible, tooLarge, invalidRecord, random, configuration, conflict
    var errorDescription: String? {
        switch self {
        case .configuration: return sidText("Общий доступ к сейфу не настроен в подписи приложения. Проверьте App Groups и Keychain Sharing.", "Shared vault access is not configured in app signing. Check App Groups and Keychain Sharing.")
        case .conflict: return sidText("Запись уже изменена. Откройте её снова перед редактированием.", "This item has changed. Reopen it before editing.")
        case .locked: return sidText("Сейф заблокирован. Откройте его снова.", "The vault is locked. Unlock it again.")
        case .missingKey: return sidText("Ключ сейфа недоступен. Существующие данные не изменены.", "The vault key is unavailable. Existing data was not changed.")
        case .passcode: return sidText("Для сейфа нужен код-пароль устройства.", "Set a device passcode to use the vault.")
        case .storage: return sidText("Не удалось прочитать или сохранить сейф. Данные не заменены.", "Could not read or save the vault. Data was not replaced.")
        case .incompatible: return sidText("Формат сейфа не поддерживается. Данные не изменены.", "Unsupported vault format. Data was not changed.")
        case .tooLarge: return sidText("Лимит: 10 МБ на документ, 30 МБ на сейф.", "Limit: 10 MB per document, 30 MB per vault.")
        case .invalidRecord: return sidText("Заполните название и обязательные поля.", "Complete the title and required fields.")
        case .random: return sidText("Не удалось создать пароль. Повторите попытку.", "Could not generate a password. Try again.")
        }
    }
}

// Version-bound authenticated encryption; corrupt or wrong-key data is never treated as empty.
enum SpyderIDCodec {
    static let aad = Data("com.spyder.id.vault.v1".utf8)
    static func seal(_ records: [SpyderIDRecord], key: SymmetricKey) throws -> Data {
        let clear = try JSONEncoder().encode(SpyderIDPayload(version: records.contains { $0.passkey != nil } ? 2 : 1, records: records))
        guard clear.count <= 30 * 1024 * 1024 else { throw SpyderIDFailure.tooLarge }
        guard let data = try AES.GCM.seal(clear, using: key, authenticating: aad).combined else {
            throw SpyderIDFailure.storage
        }
        return data
    }
    static func open(_ data: Data, key: SymmetricKey) throws -> [SpyderIDRecord] {
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: aad)
        let payload = try JSONDecoder().decode(SpyderIDPayload.self, from: plain)
        guard [1, 2].contains(payload.version) else { throw SpyderIDFailure.incompatible }
        return payload.records
    }
    static func password() throws -> String {
        // Rejection sampling avoids modulo bias and requires all four character classes.
        let classes = [Array("ABCDEFGHJKLMNPQRSTUVWXYZ"), Array("abcdefghijkmnopqrstuvwxyz"), Array("23456789"), Array("!@#$%*-_+")]
        let alphabet = classes.flatMap { $0 }
        while true {
            var chars: [Character] = []
            while chars.count < 24 {
                var byte: UInt8 = 0
                guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else { throw SpyderIDFailure.random }
                let ceiling = 256 - (256 % alphabet.count)
                if Int(byte) < ceiling { chars.append(alphabet[Int(byte) % alphabet.count]) }
            }
            if classes.allSatisfy({ group in chars.contains(where: { group.contains($0) }) }) { return String(chars) }
        }
    }
}


func sidText(_ ru: String, _ en: String) -> String {
    Locale.current.language.languageCode?.identifier == "ru" ? ru : en
}
