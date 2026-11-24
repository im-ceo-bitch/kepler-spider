import Foundation

/// A single-use authentication attempt. All access is serialized by WalletAccess on MainActor.
/// No authentication result is reusable after lock(), including a delayed success callback.
struct WalletUnlockGate {
    private var pending: UUID?

    mutating func begin() -> UUID? {
        guard pending == nil else { return nil }
        let id = UUID()
        pending = id
        return id
    }

    mutating func cancel() { pending = nil }

    mutating func finish(_ id: UUID) -> Bool {
        guard pending == id else { return false }
        pending = nil
        return true
    }
}
