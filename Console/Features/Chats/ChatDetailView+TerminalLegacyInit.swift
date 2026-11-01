import SwiftUI

// Backward-compatible initializer for the legacy terminal wrapper.
// It permits that wrapper's original ChatDetailView call sites to compile
// without replacing the current 35-command action registry or changing E2EE.
// Wallet activity is routed explicitly by the parent in primary chat navigation.
extension ChatDetailView {
    init(contact: WalletContact,
         onBack: @escaping () -> Void,
         onAction: @escaping (WalletModal) -> Void) {
        self.init(contact: contact,
                  onBack: onBack,
                  onAction: onAction,
                  onOpenActivity: {})
    }
}
