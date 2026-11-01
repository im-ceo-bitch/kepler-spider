import SwiftUI

// Spyder Chat is the active chat implementation. The legacy Console screen remains
// in the repository for migration, but must never override the deployed Spyder API.
struct ChatsHomeView: View {
    let onOpen: (WalletContact) -> Void
    let onAdd: () -> Void
    var onProfile: () -> Void = {}
    var isActive: Bool = true

    var body: some View {
        SpyderDevnetChatsHomeView(onOpen: onOpen, onAdd: onAdd, onProfile: onProfile, isActive: isActive)
    }
}
