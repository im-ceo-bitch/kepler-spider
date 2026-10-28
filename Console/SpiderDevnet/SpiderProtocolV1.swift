import Foundation
import Combine
import CryptoKit
import CommonCrypto
import Security

// Compatibility adapter for kepler-blockchain-main / Spider Protocol v0.1.
// Experimental derivation profile is wallet-specific and MUST be coordinated before mainnet.
// 12/24-word BIP39 -> PBKDF2-HMAC-SHA512 -> SLIP-0010 Ed25519 hardened m/44'/9999'/0'/0'.
// Public key -> SHA256(pk)[0..20] -> Bech32m HRP "spider".
// Signed transfers exactly match SPIDER/TX/TRANSFER/V1\0 canonical preimage in Rust.

enum SpiderProtocolV1 {
    static let chainId = "spider-devnet-1"
    static let decimals = 9
    static let gasUnits: UInt64 = 21_000
    static let derivation = "m/44'/9999'/0'/0'" // temporary wallet devnet profile, not a public coin type

    enum Failure: LocalizedError {
        case invalidMnemonic, derivationFailure, badAmount, invalidAddress, badVector
        var errorDescription: String? {
            switch self {
            case .invalidMnemonic: "Невозможно вычислить ключ из фразы BIP-39."
            case .derivationFailure: "Ошибка формирования ключа Spider Devnet."
            case .badAmount: "Некорректная сумма SPD. Поддерживается до 9 знаков после запятой."
            case .invalidAddress: "Адрес Spider должен быть корректным Bech32m spider1…"
            case .badVector: "Контрольный тест Spider Protocol не пройден."
            }
        }
    }

    struct Account {
        let address: String
        let publicKeyHex: String
    }
    struct Transfer: Codable {
        let chain_id: String
        let sender: String
        let recipient: String
        let asset_id: String
        let amount: UInt64
        let nonce: UInt64
        let gas_limit: UInt64
        let max_fee_per_gas: UInt64
        let expiry_height: UInt64
    }
    struct SignedTransfer: Codable {
        let payload: Transfer
        let public_key: String
        let signature: String
    }

    private static func hmac(_ bytes: Data, key: Data) -> Data {
        let mac = HMAC<SHA512>.authenticationCode(for: bytes, using: SymmetricKey(data: key))
        return Data(mac)
    }

    private static func privateKey(mnemonic: String) throws -> Curve25519.Signing.PrivateKey {
        let words = mnemonic.decomposedStringWithCompatibilityMapping
        let salt = "mnemonic".decomposedStringWithCompatibilityMapping
        var seed = [UInt8](repeating: 0, count: 64)
        let saltBytes = Array(salt.utf8)
        let derivedKeyCount = seed.count
        let status = words.withCString { password in
            saltBytes.withUnsafeBufferPointer { buffer in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password,
                    words.lengthOfBytes(using: .utf8), buffer.baseAddress, saltBytes.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512), 2048, &seed, derivedKeyCount)
            }
        }
        guard status == kCCSuccess else { throw Failure.derivationFailure }
        var material = hmac(Data(seed), key: Data("ed25519 seed".utf8))
        // SLIP-0010 Ed25519 supports hardened children only.
        for child in [UInt32(44), 9999, 0, 0] {
            let hardened = child | 0x8000_0000
            var data = Data([0]); data.append(material.prefix(32))
            for shift in stride(from: 24, through: 0, by: -8) {
                data.append(UInt8(truncatingIfNeeded: hardened >> UInt32(shift)))
            }
            material = hmac(data, key: Data(material.suffix(32)))
        }
        guard material.count == 64 else { throw Failure.derivationFailure }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: Data(material.prefix(32)))
    }

    static func account(mnemonic: String) throws -> Account {
        let key = try privateKey(mnemonic: mnemonic)
        let publicBytes = key.publicKey.rawRepresentation
        let digest = Data(SHA256.hash(data: publicBytes))
        let addr = try encodeAddress(Data(digest.prefix(20)))
        return Account(address: addr, publicKeyHex: publicBytes.map { String(format: "%02x", $0) }.joined())
    }

    static func verifyPublicTestVector() throws {
        let fixture = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let expectedPublicKey = "a20a6cddb7cf52fbe4403024e1ce8463ac0d70870bac6f492f5d16ba405fde12"
        let expectedAddress = "spider134e7kqt50ferckw9tywcvwdlyp54sp8hz44efd"
        let actual = try account(mnemonic: fixture)
        guard actual.publicKeyHex == expectedPublicKey, actual.address == expectedAddress,
              isValidAddress(actual.address) else { throw Failure.badVector }
    }

    static func amountUnits(_ raw: String) throws -> UInt64 {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let parts = clean.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let first = parts.first, !first.isEmpty,
              first.allSatisfy({ $0.isNumber }),
              let integer = UInt64(first),
              (parts.count == 1 || (parts[1].count <= 9 && parts[1].allSatisfy({ $0.isNumber }))) else { throw Failure.badAmount }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        let (whole, overflow) = integer.multipliedReportingOverflow(by: 1_000_000_000)
        guard !overflow,
              let frac = UInt64(fraction.padding(toLength: 9, withPad: "0", startingAt: 0)),
              whole <= UInt64.max - frac else { throw Failure.badAmount }
        return whole + frac
    }

    private static let alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static func polymod(_ input: [UInt8]) -> UInt32 {
        let gen: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var check: UInt32 = 1
        for value in input {
            let top = check >> 25
            check = (check & 0x1ff_ffff) << 5 ^ UInt32(value)
            for i in 0..<5 where ((top >> i) & 1) == 1 { check ^= gen[i] }
        }
        return check
    }
    private static func expand(_ hrp: String) -> [UInt8] {
        let chars = Array(hrp.utf8)
        return chars.map { $0 >> 5 } + [0] + chars.map { $0 & 31 }
    }
    private static func convert(_ bytes: [UInt8], from: Int, to: Int, pad: Bool) -> [UInt8]? {
        var acc = 0, bits = 0
        let mask = (1 << to) - 1
        var out: [UInt8] = []
        for byte in bytes {
            let value = Int(byte)
            if value >> from != 0 { return nil }
            acc = (acc << from | value) & 0xffff
            bits += from
            while bits >= to { bits -= to; out.append(UInt8((acc >> bits) & mask)) }
        }
        if pad { if bits > 0 { out.append(UInt8((acc << (to - bits)) & mask)) } }
        else if bits >= from || ((acc << (to - bits)) & mask) != 0 { return nil }
        return out
    }
    private static func encodeAddress(_ digest: Data) throws -> String {
        guard digest.count == 20, let five = convert(Array(digest), from: 8, to: 5, pad: true) else { throw Failure.invalidAddress }
        let hrp = "spider"
        let pre = expand(hrp) + five + Array(repeating: UInt8(0), count: 6)
        let checksum = polymod(pre) ^ 0x2bc830a3
        let checks: [UInt8] = (0..<6).map { UInt8((checksum >> UInt32(5 * (5 - $0))) & 31) }
        return hrp + "1" + String((five + checks).map { alphabet[Int($0)] })
    }
    static func isValidAddress(_ address: String) -> Bool {
        guard address == address.lowercased(), address.hasPrefix("spider1") else { return false }
        let body = Array(address.dropFirst(7))
        guard body.count == 38 else { return false }  // 20 bytes => 32 base32 + 6 checksum
        let indexes = body.compactMap { alphabet.firstIndex(of: $0) }
        guard indexes.count == body.count else { return false }
        let values = indexes.map { UInt8($0) }
        guard polymod(expand("spider") + values) == 0x2bc830a3 else { return false }
        guard let raw = convert(Array(values.dropLast(6)), from: 5, to: 8, pad: false) else { return false }
        return raw.count == 20
    }
    private static func encodeString(_ value: String, into bytes: inout Data) {
        let data = Data(value.utf8)
        let n = UInt32(data.count)
        for shift in stride(from: 24, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: n >> UInt32(shift))) }
        bytes.append(data)
    }
    private static func encodeNumber(_ value: UInt64, into bytes: inout Data) {
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift))) }
    }
    static func signingBytes(_ p: Transfer) -> Data {
        var bytes = Data("SPIDER/TX/TRANSFER/V1\0".utf8)
        for value in [p.chain_id, p.sender, p.recipient, p.asset_id] { encodeString(value, into: &bytes) }
        for value in [p.amount, p.nonce, p.gas_limit, p.max_fee_per_gas, p.expiry_height] { encodeNumber(value, into: &bytes) }
        return bytes
    }
    // Caller MUST obtain authoritative nonce, height, chain ID, and fee from an authenticated RPC.
    // v0.5 does NOT submit transfers because Spider Chain v0.1 exposes no RPC.
    static func sign(_ transfer: Transfer, mnemonic: String) throws -> SignedTransfer {
        guard transfer.chain_id == chainId, transfer.asset_id == "SPD", transfer.amount > 0,
              transfer.gas_limit >= gasUnits, transfer.max_fee_per_gas > 0,
              isValidAddress(transfer.sender), isValidAddress(transfer.recipient) else { throw Failure.invalidAddress }
        let key = try privateKey(mnemonic: mnemonic)
        let account = try account(mnemonic: mnemonic)
        guard account.address == transfer.sender else { throw Failure.invalidAddress }
        let signature = try key.signature(for: signingBytes(transfer))
        return SignedTransfer(payload: transfer, public_key: account.publicKeyHex,
            signature: signature.map { String(format: "%02x", $0) }.joined())
    }
}

@MainActor
final class SpiderDevnetStore: ObservableObject {
    @Published private(set) var address: String?
    @Published private(set) var busy = false
    @Published var error: String?
    func clear() { address = nil }
    func deriveAddress() {
        guard !busy else { return }
        busy = true
        Task {
            do {
                let a = try await Task.detached(priority: .userInitiated) {
                    try SpiderProtocolV1.verifyPublicTestVector()
                    let words = try WalletVault.revealForBackup()
                    return try SpiderProtocolV1.account(mnemonic: words.joined(separator: " ")).address
                }.value
                address = a
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
