import Foundation

/// Conservative address syntax and checksum validation for currently supported receiving networks.
/// A syntactically valid address NEVER establishes recipient identity or ownership.
/// No external network or secret material is used in this code.
enum WalletRecipientValidation: Equatable {
    case valid
    case invalid(String)
}

enum WalletAddressValidator {
    static func check(_ raw: String, for chain: SpyderChain, legacyStorage: Bool = false) -> WalletRecipientValidation {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch chain {
        case .ethereum:
            guard value.range(of: "^0x[0-9a-fA-F]{40}$", options: .regularExpression) != nil else {
                return .invalid("Адрес Ethereum должен содержать 0x и ровно 40 шестнадцатеричных символов.")
            }
            // EIP-55 checksums require Keccak-256, not SHA3-256.
            // Existing saved records remain readable; every new use is checked normally.
            if !legacyStorage {
                guard value != "0x" + String(repeating: "0", count: 40) else {
                    return .invalid("Нулевой Ethereum-адрес недопустим для перевода.")
                }
                guard validEthereumChecksum(value) else {
                    return .invalid("Контрольная сумма Ethereum (EIP-55) не совпадает. Скопируйте адрес заново.")
                }
            }
            return .valid
        case .solana:
            guard let decoded = decodeBase58(value), decoded.count == 32 else {
                return .invalid("Публичный ключ Solana должен декодироваться в 32 байта Base58.")
            }
            return .valid
        case .bitcoin:
            guard validateSegwit(value) else {
                return .invalid("Bitcoin mainnet: требуется корректный bc1 адрес с Bech32/Bech32m контрольной суммой.")
            }
            return .valid
        }
    }

    // Lowercase/uppercase-only hex addresses remain compatible with EIP-55 conventions.
    // Mixed-case addresses must match the exact checksum; never repair them silently.
    private static func validEthereumChecksum(_ value: String) -> Bool {
        let body = String(value.dropFirst(2))
        let lower = body.lowercased()
        if body == lower || body == body.uppercased() { return true }
        let hash = Array(WalletEVMKeccak256.hash(Data(lower.utf8)))
        let original = Array(body.utf8)
        for (i, char) in lower.utf8.enumerated() where (97...102).contains(char) {
            let nibble = i.isMultiple(of: 2) ? hash[i / 2] >> 4 : hash[i / 2] & 15
            let expected = nibble >= 8 ? char - 32 : char
            guard original[i] == expected else { return false }
        }
        return true
    }

    /// Solana Base58 is case-sensitive; hex and valid SegWit strings are not.
    static func sameAddress(_ lhs: String, _ rhs: String, for chain: SpyderChain) -> Bool {
        switch chain {
        case .solana: return lhs == rhs
        case .ethereum, .bitcoin: return lhs.caseInsensitiveCompare(rhs) == .orderedSame
        }
    }

    private static func decodeBase58(_ value: String) -> [UInt8]? {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        guard !value.isEmpty && value.count <= 60 else { return nil }
        var result: [UInt8] = [] // big-endian magnitude, excluding leading zeros
        for c in value {
            guard let digit = alphabet.firstIndex(of: c) else { return nil }
            var carry = digit
            for index in result.indices.reversed() {
                let next = Int(result[index]) * 58 + carry
                result[index] = UInt8(next & 255)
                carry = next >> 8
            }
            while carry > 0 {
                result.insert(UInt8(carry & 255), at: 0)
                carry >>= 8
            }
            if result.count > 32 { return nil }
        }
        let leading = value.prefix(while: { $0 == "1" }).count
        let bytes = Array(repeating: UInt8(0), count: leading) + result
        return bytes.count <= 32 ? bytes : nil
    }

    private static func validateSegwit(_ original: String) -> Bool {
        guard original.count >= 14 && original.count <= 90, original.isASCII else { return false }
        let lower = original.lowercased()
        guard original == lower || original == original.uppercased(), lower.hasPrefix("bc1") else { return false }
        let chars = Array(lower)
        guard let separator = chars.lastIndex(of: "1"), separator >= 2, separator + 7 <= chars.count else { return false }
        let alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        var data: [Int] = []
        for char in chars[(separator + 1)...] {
            guard let value = alphabet.firstIndex(of: char) else { return false }
            data.append(value)
        }
        guard data.count >= 7 else { return false }
        let version = data[0]
        guard (0...16).contains(version) else { return false }
        let checksum = polymod(hrpExpanded: [3, 3, 0, 2, 3], data: data)
        let expected = version == 0 ? 1 : 0x2bc830a3
        guard checksum == expected else { return false }
        let payload = Array(data.dropFirst().dropLast(6))
        guard let decoded = convertFiveToEight(payload), (2...40).contains(decoded.count) else { return false }
        if version == 0 { return decoded.count == 20 || decoded.count == 32 }
        return true
    }

    private static func polymod(hrpExpanded: [Int], data: [Int]) -> Int {
        let generators = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk = 1
        for value in hrpExpanded + data {
            let top = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ value
            for bit in 0..<5 where (top >> bit) & 1 == 1 {
                chk ^= generators[bit]
            }
        }
        return chk
    }

    private static func convertFiveToEight(_ data: [Int]) -> [UInt8]? {
        var accumulator = 0
        var bits = 0
        var result: [UInt8] = []
        for value in data {
            guard (0..<32).contains(value) else { return nil }
            accumulator = ((accumulator << 5) | value) & 0xfff
            bits += 5
            if bits >= 8 {
                bits -= 8
                result.append(UInt8((accumulator >> bits) & 0xff))
            }
        }
        guard bits < 5, ((accumulator << (8 - bits)) & 0xff) == 0 else { return nil }
        return result
    }
}

private extension String {
    var isASCII: Bool { unicodeScalars.allSatisfy { $0.value < 128 } }
}
