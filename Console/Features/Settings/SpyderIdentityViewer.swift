import SwiftUI

struct SpyderIdentityViewer: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SpyderMotionKeys.enabled) private var motionEnabled = true

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 20)
                    SpyderProfileAvatarView(motion: chat.myAvatar?.motion ?? .pulse,
                        accent: chat.myAvatar?.color ?? .blue,
                        diameter: max(1, min(geometry.size.width - 40, geometry.size.height * 0.65)),
                        animate: motionEnabled, seed: chat.myAvatar?.seed ?? "", cornerRadius: 8,
                        ringStyle: chat.personaStyle.ring)
                    Label(chat.myName, systemImage: chat.personaStyle.badge.symbol)
                        .font(.title.bold()).multilineTextAlignment(.center)
                    if !chat.myUsername.isEmpty { Text("@" + chat.myUsername).font(.headline).foregroundStyle(.white.opacity(0.7)) }
                    if !chat.myBio.isEmpty { Text(chat.myBio).font(.body).multilineTextAlignment(.center) }
                    if !chat.myStatus.isEmpty { Text(chat.myStatus).font(.callout).foregroundStyle(.white.opacity(0.7)) }
                    Label(chat.personaPrivacy.title, systemImage: chat.personaPrivacy.symbol)
                        .font(.caption).foregroundStyle((chat.myAvatar?.color ?? .blue).color)
                    Spacer(minLength: 20)
                }.padding(20).frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Label("Закрыть", systemImage: "xmark").font(.subheadline.bold()).padding(14)
                }.foregroundStyle(.white)
            }.padding(.horizontal, 10).background(.black)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.height > 120 && abs(value.translation.width) < value.translation.height { dismiss() }
        })
        .accessibilityAction(.escape) { dismiss() }
    }
}
