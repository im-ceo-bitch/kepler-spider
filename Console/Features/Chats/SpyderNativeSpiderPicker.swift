import SwiftUI

/// Legacy compatibility only. The decorative picker is intentionally hidden
/// from the release UX. Its settings remain decodable for previously saved data.
struct SpyderNativeSpiderPicker: View {
    @Binding var appearance: SpyderChatAppearance
    let fallbackAccent: Color

    init(appearance: Binding<SpyderChatAppearance>, fallbackAccent: Color) {
        self._appearance = appearance
        self.fallbackAccent = fallbackAccent
    }

    var body: some View {
        EmptyView()
            .accessibilityHidden(true)
    }
}
