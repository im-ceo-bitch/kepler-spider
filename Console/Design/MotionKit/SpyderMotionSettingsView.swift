import SwiftUI
import UIKit

/// Personalization lives independently of wallet/chain operations and is safe to present as a sheet.
struct SpyderMotionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SpyderMotionKeys.accent) private var accentValue = SpyderSignalAccent.red.rawValue
    @AppStorage(SpyderMotionKeys.avatar) private var avatarValue = SpyderAvatarMotion.pulse.rawValue
    @AppStorage(SpyderMotionKeys.launch) private var launchValue = SpyderLaunchMotion.particles.rawValue
    @AppStorage(SpyderMotionKeys.enabled) private var motionEnabled = true
    @AppStorage(SpyderMotionKeys.launchEveryTime) private var launchEveryTime = false
    @State private var showLaunchPreview = false

    private var currentAccent: SpyderSignalAccent {
        SpyderSignalAccent(rawValue: accentValue) ?? .red
    }
    private var currentAvatar: SpyderAvatarMotion {
        SpyderAvatarMotion(rawValue: avatarValue) ?? .pulse
    }
    private var currentLaunch: SpyderLaunchMotion {
        SpyderLaunchMotion(rawValue: launchValue) ?? .particles
    }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Motion Studio")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Твоя сеть. Твой характер.")
                            .font(.system(size: 14))
                            .foregroundStyle(WalletTheme.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Цвет сигнала")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                            ForEach(SpyderSignalAccent.allCases) { option in
                                Button {
                                    accentValue = option.rawValue
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    HStack(spacing: 10) {
                                        Circle().fill(option.color).frame(width: 18, height: 18)
                                        Text(LocalizedStringKey(option.title))
                                            .font(.system(size: 13, weight: .semibold))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                        if currentAccent == option {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(option.color)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 10)
                                    .background(WalletTheme.surface,
                                                in: RoundedRectangle(cornerRadius: 17))
                                    .overlay(RoundedRectangle(cornerRadius: 17)
                                        .stroke(currentAccent == option ? option.color : WalletTheme.divider,
                                                lineWidth: currentAccent == option ? 2 : 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(currentAccent == option ? .isSelected : [])
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        sectionTitle("Мой анимированный аватар")
                        HStack {
                            Spacer()
                            SpyderProfileAvatarView(motion: currentAvatar, accent: currentAccent,
                                                    diameter: 156, animate: motionEnabled)
                                .id(avatarValue)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        Text(LocalizedStringKey(currentAvatar.title))
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                                  spacing: 10) {
                            ForEach(SpyderAvatarMotion.allCases) { option in
                                Button {
                                    avatarValue = option.rawValue
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: option.symbol)
                                            .font(.system(size: 25, weight: .light))
                                            .foregroundStyle(currentAvatar == option ? currentAccent.color : WalletTheme.ink)
                                            .frame(height: 33)
                                        Text(LocalizedStringKey(option.title))
                                            .font(.system(size: 11, weight: currentAvatar == option ? .bold : .medium))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.78)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 75)
                                    .padding(.vertical, 7)
                                    .background(WalletTheme.surface,
                                                in: RoundedRectangle(cornerRadius: 18))
                                    .overlay(RoundedRectangle(cornerRadius: 18)
                                        .stroke(currentAvatar == option ? currentAccent.color : WalletTheme.divider,
                                                lineWidth: currentAvatar == option ? 2 : 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(currentAvatar == option ? .isSelected : [])
                            }
                        }
                        Text("12 стилей · выбранный аватар будет использоваться в профиле.")
                            .font(.system(size: 12))
                            .foregroundStyle(WalletTheme.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Анимация запуска")
                        VStack(spacing: 0) {
                            ForEach(SpyderLaunchMotion.allCases) { option in
                                Button {
                                    launchValue = option.rawValue
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: option == .particles ? "circle.hexagongrid.fill"
                                              : option == .eye ? "eye" : "forward.end")
                                            .frame(width: 24)
                                            .foregroundStyle(currentAccent.color)
                                        Text(LocalizedStringKey(option.title))
                                            .font(.system(size: 15))
                                        Spacer()
                                        Image(systemName: currentLaunch == option ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(currentLaunch == option ? currentAccent.color : WalletTheme.secondary)
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 15)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(currentLaunch == option ? .isSelected : [])
                                if option != SpyderLaunchMotion.allCases.last { Divider() }
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                        Button { showLaunchPreview = true } label: {
                            Label("Посмотреть заставку", systemImage: "play.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .foregroundStyle(.white)
                                .background(Color(red: 0.13, green: 0.14, blue: 0.16), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Поведение")
                        Toggle("Анимации Motion Kit", isOn: $motionEnabled)
                        Toggle("Заставка при каждом запуске", isOn: $launchEveryTime)
                            .disabled(!motionEnabled || currentLaunch == .simple)
                        Text("Если анимации отключены или в iPhone включено «Уменьшение движения», показываем статичный логотип. По умолчанию заставка проигрывается только один раз, при первом открытии.")
                            .font(.system(size: 12))
                            .foregroundStyle(WalletTheme.secondary)
                    }
                    .tint(currentAccent.color)
                    .padding(16)
                    .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                .foregroundStyle(WalletTheme.ink)
                .padding(20)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .navigationTitle("Персонализация")
            .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showLaunchPreview) {
            SpyderLaunchPreview(motion: currentLaunch, accent: currentAccent)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 19, weight: .bold))
    }
}

private struct SpyderLaunchPreview: View {
    @Environment(\.dismiss) private var dismiss
    let motion: SpyderLaunchMotion
    let accent: SpyderSignalAccent

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Group {
                    switch motion {
                    case .particles:
                        SpyderParticleLogoView(accent: accent, loops: true)
                            .frame(width: 250, height: 250)
                    case .eye:
                        NativeEyeAnimationView(duration: 4.2, repeats: true, accent: accent)
                            .frame(maxWidth: 350)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    case .simple:
                        Image("SpyderLaunchLogo")
                            .resizable().renderingMode(.template).scaledToFit()
                            .foregroundStyle(accent.color)
                            .frame(width: 166, height: 166)
                    }
                }
                Image("SpyderBrandText")
                    .resizable().renderingMode(.template).scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: 200, height: 65)
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(.white)
                            .background(.white.opacity(0.15), in: Circle())
                    }
                    .accessibilityLabel("Закрыть предпросмотр")
                }
                Spacer()
                Text("Предпросмотр · можно закрыть в любой момент")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SpyderMotionSettingsView()
}
