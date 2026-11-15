import XCTest
import CryptoKit
@testable import Console

final class SpyderIDCodecTests: XCTestCase {
    func testRoundTripPreservesSecretsAndAttachmentExactly() throws {
        let key = SymmetricKey(size: .bits256)
        var password = SpyderIDRecord(kind: .passwords)
        password.title = "Site"; password.website = "https://example.com"
        password.username = "alex@example.com"; password.password = "  Päss🔒word\n "
        var document = SpyderIDRecord(kind: .documents)
        document.title = "Insurance"; document.fileName = "insurance.pdf"
        document.fileData = Data((0..<255).map { UInt8($0) })
        let records = [password, document]
        let data = try SpyderIDCodec.seal(records, key: key)
        XCTAssertEqual(try SpyderIDCodec.open(data, key: key), records)
        XCTAssertNil(data.range(of: Data(password.username.utf8)))
        XCTAssertNil(data.range(of: Data(password.password.utf8)))
    }
    func testWrongKeyAndTamperingFailClosed() throws {
        let key = SymmetricKey(size: .bits256)
        let original = try SpyderIDCodec.seal([], key: key)
        XCTAssertThrowsError(try SpyderIDCodec.open(original, key: SymmetricKey(size: .bits256)))
        var changed = original
        changed[changed.count - 1] ^= 1
        XCTAssertThrowsError(try SpyderIDCodec.open(changed, key: key))
        XCTAssertThrowsError(try SpyderIDCodec.open(Data(original.prefix(8)), key: key))
    }
    func testEachSaveUsesFreshNonce() throws {
        let key = SymmetricKey(size: .bits256)
        XCTAssertNotEqual(try SpyderIDCodec.seal([], key: key), try SpyderIDCodec.seal([], key: key))
    }
    func testUnsupportedVersionIsNotAnEmptyVault() throws {
        let key = SymmetricKey(size: .bits256)
        let clear = Data("{\"version\":999,\"records\":[]}".utf8)
        let sealed = try AES.GCM.seal(clear, using: key, authenticating: SpyderIDCodec.aad).combined!
        XCTAssertThrowsError(try SpyderIDCodec.open(sealed, key: key))
    }
    func testGeneratorProduces24CharactersAndAllClasses() throws {
        let classes = ["ABCDEFGHJKLMNPQRSTUVWXYZ", "abcdefghijkmnopqrstuvwxyz", "23456789", "!@#$%*-_+"]
        var values = Set<String>()
        for _ in 0..<64 {
            let password = try SpyderIDCodec.password()
            XCTAssertEqual(password.count, 24)
            for group in classes { XCTAssertTrue(password.contains { group.contains($0) }) }
            values.insert(password)
        }
        XCTAssertEqual(values.count, 64)
    }
}

extension SpyderIDCodecTests {
    func testExactDomainMatchingRejectsLookalikesAndSubdomains() {
        var record = SpyderIDRecord(kind: .passwords)
        record.website = "https://accounts.example.com/login"
        XCTAssertTrue(SpyderIDRepository.matches(record, host: "accounts.example.com"))
        XCTAssertFalse(SpyderIDRepository.matches(record, host: "accounts.example.com.evil.test"))
        XCTAssertFalse(SpyderIDRepository.matches(record, host: "example.com"))
        XCTAssertFalse(SpyderIDRepository.matches(record, host: "evil-accounts.example.com"))
        XCTAssertNil(SpyderIDRepository.host("https://user:secret@example.com"))
        XCTAssertNil(SpyderIDRepository.host("javascript:alert(1)"))
    }
    func testOldRecordWithoutDraftFlagStillDecodes() throws {
        let id = UUID()
        let json = "{\"id\":\"\(id.uuidString)\",\"kind\":\"passwords\",\"title\":\"Test\",\"website\":\"example.com\",\"username\":\"alex\",\"password\":\"secret\",\"note\":\"\",\"modified\":0}"
        let record = try JSONDecoder().decode(SpyderIDRecord.self, from: Data(json.utf8))
        XCTAssertNil(record.isDraft)
        XCTAssertEqual(record.password, "secret")
    }
    func testRepositoryValidationRejectsMissingSecretsAndOversizedFiles() {
        var record = SpyderIDRecord(kind: .passwords)
        record.title = "Account"; record.username = "alex"
        XCTAssertThrowsError(try SpyderIDRepository.validate(record))
        record.password = " secret "
        XCTAssertNoThrow(try SpyderIDRepository.validate(record))
        record.kind = .documents
        XCTAssertThrowsError(try SpyderIDRepository.validate(record))
        record.fileData = Data(count: 10 * 1024 * 1024 + 1)
        XCTAssertThrowsError(try SpyderIDRepository.validate(record))
    }
}
