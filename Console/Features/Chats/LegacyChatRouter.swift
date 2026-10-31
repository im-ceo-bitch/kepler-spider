import SwiftUI

// Spyder Chat is the active chat implementation. The legacy Console screen remains
// in the repository for migration, but must never override the deployed Spyder API.
struct ChatsHomeView: View {
    let onOpen: (WalletContact) -> Void
    let onAdd: () -> Void

    var body: some View {
        SpyderDevnetChatsHomeView(onOpen: onOpen, onAdd: onAdd)
    }
}
