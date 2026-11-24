import Foundation

/// Reference pre-license APDU contract, not a Tangem/EMV applet. The integrator must
/// obtain a registered AID and implement/audit the corresponding secure-element firmware.
public struct CardCommand: Sendable, Equatable {
    public let instruction: UInt8, p1: UInt8, data: Data, expectedLength: Int
    public init(instruction:UInt8,p1:UInt8=0,data:Data=Data(),expectedLength:Int=0) {self.instruction=instruction;self.p1=p1;self.data=data;self.expectedLength=expectedLength}
}
public protocol CardChannel: Sendable {
    func exchange(_ command: CardCommand) async throws -> Data
}
public enum CardPurpose: Sendable, Equatable { case enroll(publicKey: Data); case invoice(id:String, merchant:String, amount:Int64) }
public enum CardProtocol {
    /// A key is obtained only from the selected applet. Private-key export is never requested.
    public static func publicKey(on channel: any CardChannel) async throws -> Data {
        let bytes=try await channel.exchange(CardCommand(instruction:0x20,expectedLength:65))
        guard bytes.count==65,bytes.first==4 else {throw WalletError.unsupportedCard};return bytes
    }
    /// Confirm user intent on the phone first. This possession proof is NOT payment authorization.
    /// No PIN is transferred by this reference transport; a selected/audited applet must enforce its own authentication policy.
    public static func sign(_ challenge:CardChallenge,expected:CardPurpose,on channel:any CardChannel) async throws -> Data {
        let msg=try challenge.message()
        guard let f=try JSONSerialization.jsonObject(with:msg) as? [Any], let keyHex=f[7] as? String, let key=Data(strictHex:keyHex), key.count==65,key.first==4 else {throw WalletError.invalidResponse}
        switch expected {
        case .enroll(let pub): guard f[5] as? String=="enroll",key==pub,f[9] is NSNull,f[10] is NSNull,f[11] is NSNull else {throw WalletError.mismatch}
        case .invoice(let id,let merchant,let amount):
            guard f[5] as? String=="invoice_preview",f[9] as? String==id,f[10] as? String==merchant,(f[11] as? NSNumber)?.int64Value==amount,f[12] as? String=="UZS",amount>0 else {throw WalletError.mismatch}
        }
        guard try await publicKey(on:channel)==key else {throw WalletError.mismatch}
        // Begin resets applet state. Chunked transfer avoids relying on extended APDU support.
        guard msg.count<=2048 else {throw WalletError.invalidInput}
        let length=Data([UInt8(msg.count>>8),UInt8(msg.count&255)])
        guard try await channel.exchange(CardCommand(instruction:0x30,data:length)).isEmpty else {throw WalletError.unsupportedCard}
        for i in stride(from:0,to:msg.count,by:200) {
            let data=msg.subdata(in:i..<min(i+200,msg.count))
            guard try await channel.exchange(CardCommand(instruction:0x31,data:data)).isEmpty else {throw WalletError.unsupportedCard}
        }
        let sig=try await channel.exchange(CardCommand(instruction:0x32,expectedLength:72))
        guard (8...72).contains(sig.count),sig.first==0x30 else {throw WalletError.unsupportedCard};return sig
    }
}
#if canImport(CoreNFC) && os(iOS) && !targetEnvironment(macCatalyst)
import CoreNFC
/// Use only a tag from a foreground NFCTagReaderSession, with the integrator's registered AID
/// in Info.plist. The session delegate must connect to the intended ISO7816 tag first.
@available(iOS 17.0, *)
public actor ISO7816CardChannel: CardChannel {
    private let tag: NFCISO7816Tag
    public init(connectedTag: NFCISO7816Tag) { tag=connectedTag }
    public func exchange(_ command: CardCommand) async throws -> Data {
        guard [0x20,0x30,0x31,0x32].contains(command.instruction),command.data.count<=200 else {throw WalletError.invalidInput}
        let apdu=NFCISO7816APDU(instructionClass:0x80,instructionCode:command.instruction,p1Parameter:command.p1,p2Parameter:0,data:command.data,expectedResponseLength:command.expectedLength==0 ? -1 : command.expectedLength)
        return try await withCheckedThrowingContinuation { continuation in
            tag.sendCommand(apdu:apdu) { data,sw1,sw2,error in
                if let error {continuation.resume(throwing:error)}
                else if sw1==0x90 && sw2==0x00 {continuation.resume(returning:data)}
                else {continuation.resume(throwing:WalletError.unsupportedCard)}
            }
        }
    }
}
#endif
