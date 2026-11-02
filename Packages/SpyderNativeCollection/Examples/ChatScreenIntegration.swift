import SwiftUI
import SpyderNativeCollection

// EXAMPLE: paste into an iOS 17+ application and adapt your existing messages UI.
// Do not include this file in the Swift package target.
struct ExampleChatScreen: View {
    @ObservedObject var appearance: SpyderAppearanceStore
    let chatID: String

    // Parent should increment this only on actual chat navigation.
    let chatEntryNumber: Int

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Encrypted chat • \(chatID)")
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                Text("Native vector spider stays BEHIND all chat bubbles.")
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
        .background {
            SpyderChatBackground(theme: appearance.theme, entryToken: chatEntryNumber)
                .ignoresSafeArea()
        }
    }
}
