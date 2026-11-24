import Foundation
import SpyderPayKit

#if canImport(CoreNFC) && os(iOS) && !targetEnvironment(macCatalyst)
import CoreNFC

/// Reads only the selected ISO7816 application. No NDEF/raw-card fallback and
/// no debit command. Hardware entitlement and approved applet AID are required.
@MainActor
final class SpyderPayCardReader: NSObject, NFCTagReaderSessionDelegate {
    private var session: NFCTagReaderSession?
    private var continuation: CheckedContinuation<CardProof,Error>?
    private var operation: (@MainActor (any CardChannel) async throws -> CardProof)?
    private var expectedAID = ""
    private var work:Task<Void,Never>?

    static func available(aid:String?) -> Bool {
        guard let aid, NFCTagReaderSession.readingAvailable,
              let configured=Bundle.main.object(forInfoDictionaryKey:"com.apple.developer.nfc.readersession.iso7816.select-identifiers") as? [String],
              configured.contains(where:{$0.uppercased()==aid.uppercased()}) else {return false}
        return true
    }
    func run(aid:String, operation:@escaping @MainActor (any CardChannel) async throws -> CardProof) async throws -> CardProof {
        guard Self.available(aid:aid),session==nil,continuation==nil else {throw WalletError.unsupportedCard}
        let candidate:NFCTagReaderSession?=NFCTagReaderSession(pollingOption:.iso14443,delegate:self,queue:.main)
        guard let s=candidate else {throw WalletError.unsupportedCard}
        expectedAID=aid.uppercased();self.operation=operation;session=s
        s.alertMessage="Приложите совместимую тестовую Spider Card. Списания не будет."
        return try await withCheckedThrowingContinuation { c in
            continuation=c;s.begin()
        }
    }
    func cancel() {finish(.failure(CancellationError()))}
    private func finish(_ result:Result<CardProof,Error>) {
        guard let c=continuation else {return}
        continuation=nil;operation=nil
        let s=session;session=nil
        work?.cancel();work=nil
        switch result {
        case .success:s?.alertMessage="Владение тестовой картой подтверждено";s?.invalidate()
        case .failure:s?.invalidate(errorMessage:"Карта не подтверждена")
        }
        c.resume(with:result)
    }
    nonisolated func tagReaderSessionDidBecomeActive(_ session:NFCTagReaderSession) {}
    nonisolated func tagReaderSession(_ session:NFCTagReaderSession,didInvalidateWithError error:Error) {
        Task { @MainActor [weak self] in
            guard let self,self.session === session else {return}
            self.finish(.failure(error))
        }
    }
    nonisolated func tagReaderSession(_ session:NFCTagReaderSession,didDetect tags:[NFCTag]) {
        Task { @MainActor [weak self] in
            guard let self,self.session === session,self.work==nil else {return}
            guard tags.count==1,case .iso7816(let tag)=tags[0],tag.initialSelectedAID.uppercased()==self.expectedAID,
                  let operation=self.operation else {self.finish(.failure(WalletError.unsupportedCard));return}
            let selected=tags[0]
            self.work=Task { @MainActor [weak self] in
                guard let self else {return}
                do {
                    try await withCheckedThrowingContinuation { (c:CheckedContinuation<Void,Error>) in
                        session.connect(to:selected) { error in
                            if let error {c.resume(throwing:error)} else {c.resume()}
                        }
                    }
                    try Task.checkCancellation()
                    guard self.session === session else {throw CancellationError()}
                    let result=try await operation(ISO7816CardChannel(connectedTag:tag))
                    try Task.checkCancellation();self.finish(.success(result))
                } catch {self.finish(.failure(error))}
            }
        }
    }
}
#else
@MainActor
final class SpyderPayCardReader {
    static func available(aid:String?) -> Bool {false}
    func run(aid:String,operation:@escaping @MainActor (any CardChannel) async throws -> CardProof) async throws -> CardProof {throw WalletError.unsupportedCard}
    func cancel() {}
}
#endif
