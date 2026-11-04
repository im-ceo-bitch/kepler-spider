import SwiftUI
import UIKit

@MainActor
struct WalletTouchView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var touch = SpyderTouchService()
    let onConnect: (WalletContact) -> Void
    @State private var owner: String?
    @State private var server = ""
    @State private var ownCode = ""
    @State private var visible = false
    @State private var connecting = false
    @State private var connected: WalletContact?
    @State private var notice: String?
    @State private var promptReady = false
    @State private var peerAvatar: SpyderPersonaAvatar?
    @State private var completionRoute: Task<Void, Never>?
    @State private var opened = false
    @State private var attempt = UUID()

    private var visualStage: SpyderTouchConnectionVisual.Stage {
        if connected != nil { return .connected }
        if connecting || [.request, .waiting, .exchanged].contains(touch.phase) { return .encounter }
        return .searching
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title)
                                .font(.largeTitle.weight(.bold))
                                .accessibilityAddTraits(.isHeader)
                            Text(subtitle)
                                .font(.body)
                                .foregroundStyle(WalletTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .contentTransition(.opacity)

                        SpyderTouchConnectionVisual(stage: visualStage,
                            ownAvatar: chat.myAvatar, ownSeed: owner ?? "",
                            peerAvatar: peerAvatar, peerSeed: connected?.id)

                        if (touch.phase == .request || touch.phase == .waiting) && promptReady {
                            connectionRequest
                                .transition(.opacity)
                        } else if connecting {
                            ProgressView("Создаём чат…")
                        } else if connected != nil {
                            Button("Открыть чат") { routeToChat() }
                                .spyderPrimaryButton().buttonStyle(.plain)
                        } else if visualStage == .searching && notice == nil && touch.error == nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("На обоих iPhone", systemImage: "iphone")
                                    .font(.headline)
                                Text("Откройте Spyder Touch, включите Wi-Fi и разрешите поиск устройств поблизости.")
                                    .font(.subheadline).foregroundStyle(WalletTheme.secondary)
                                if !chat.myName.isEmpty {
                                    Text("Ваша личность · \(chat.myName)")
                                        .font(.footnote).foregroundStyle(WalletTheme.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                        }
                        if touch.ambiguous {
                            Label("Рядом несколько iPhone. Поднесите только тот, с которым хотите подключиться.", systemImage: "person.2")
                                .font(.callout)
                        }
                        if let message = notice ?? touch.error {
                            Label(LocalizedStringKey(message), systemImage: "info.circle").font(.callout)
                        }
                        if touch.phase == .failed {
                            Button("Открыть настройки Spyder") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }.font(.headline).frame(minHeight: 44)
                        }
                        if connected == nil && !connecting && [.idle, .failed, .exchanged].contains(touch.phase) {
                            Button("Повторить поиск") { start() }
                                .spyderPrimaryButton().buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 430, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                }
            }
            .background(Color.white.ignoresSafeArea()).foregroundStyle(WalletTheme.ink)
            .tint(WalletTheme.ink)
            .navigationTitle("Spyder Touch").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { cancel(); dismiss() }
            } }
        }
        .overlay { SpyderTouchEdgeWave(encounter: visualStage != .searching) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: promptReady)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: visualStage)
        .task { visible = true; start() }
        .task(id: visualStage) {
            promptReady = false
            guard visualStage == .encounter else { return }
            if !reduceMotion {
                do { try await Task.sleep(nanoseconds: 750_000_000) } catch { return }
            }
            guard !Task.isCancelled, visible, visualStage == .encounter else { return }
            promptReady = true
        }
        .onDisappear { visible = false; cancel() }
        .onChange(of: touch.receivedCode) { _, code in if let code { connect(code) } }
        .onChange(of: touch.phase) { _, phase in
            if phase == .request && scenePhase == .active { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        }
        .onChange(of: chat.activePersonaID) { _, _ in contextChanged() }
        .onChange(of: chat.serverAddress) { _, _ in contextChanged() }
        .onChange(of: chat.inviteCode) { _, _ in contextChanged() }
        .onChange(of: scenePhase) { _, phase in
            touch.setActive(phase == .active)
            if phase != .active { completionRoute?.cancel(); completionRoute = nil }
            if phase == .background {
                cancel()
                if connected == nil { notice = "Поиск остановлен. Вернувшись, нажми «Повторить поиск»." }
            }
        }
    }
    private var title: LocalizedStringKey {
        if connected != nil { return "Вы подключены" }
        if connecting { return "Создаём чат" }
        if touch.phase == .waiting { return "Соединяем iPhone" }
        if touch.phase == .request { return "iPhone рядом" }
        if touch.phase == .failed || notice != nil { return "Поиск остановлен" }
        return "Поднесите iPhone"
    }
    private var subtitle: LocalizedStringKey {
        if let connected { return "\(connected.name) теперь в ваших чатах" }
        if connecting { return "Завершаем подключение" }
        if touch.phase == .waiting { return "Подтвердите подключение на втором экране" }
        if touch.phase == .request { return "Сверьте код и подключитесь друг к другу" }
        if touch.phase == .failed || notice != nil { return "Проверьте подключение и попробуйте снова." }
        return "Расположите телефоны верхними краями друг к другу и задержите рядом."
    }
    private var connectionRequest: some View {
        VStack(spacing: 12) {
            Text("Код подключения").font(.footnote.weight(.semibold)).foregroundStyle(WalletTheme.secondary)
            if let comparison = touch.comparison {
                Text(comparison).font(.title.weight(.semibold).monospacedDigit()).tracking(4)
                    .accessibilityLabel(Text("Код проверки \(comparison.map(String.init).joined(separator: " "))"))
            }
            Text("Код должен совпадать на обоих iPhone.")
                .font(.footnote).foregroundStyle(WalletTheme.secondary).multilineTextAlignment(.center)
            if touch.phase == .waiting {
                ProgressView().padding(.vertical, 6)
                Button("Отменить", role: .cancel) { cancel() }.font(.subheadline).frame(minHeight: 44)
            } else {
                Button("Подключиться") { if scenePhase == .active && promptReady { touch.approve() } }
                    .spyderPrimaryButton().buttonStyle(.plain).disabled(scenePhase != .active)
                Button("Не сейчас", role: .cancel) { touch.decline() }
                    .font(.subheadline).foregroundStyle(WalletTheme.secondary).frame(minHeight: 44)
            }
            Text("Вы делитесь приглашением личности «\(chat.myName)». Деньги не отправляются.")
                .font(.caption).foregroundStyle(WalletTheme.secondary).multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
    private func routeToChat() {
        guard let connected, visible, scenePhase == .active, !opened else { return }
        opened = true
        completionRoute?.cancel(); completionRoute = nil
        touch.stop(); onConnect(connected)
    }
    private func start() {
        cancel(); connected = nil; peerAvatar = nil; opened = false; notice = nil
        guard chat.hasIdentity, chat.activePersonaID != nil,
              let normalized = SpyderChatEndpoint.normalized(chat.serverAddress) else {
            notice = "Сначала создай личность и подключись к серверу Spyder."; return
        }
        owner = chat.activePersonaID; server = normalized; ownCode = chat.inviteCode
        touch.start(server: normalized, code: ownCode)
        touch.setActive(scenePhase == .active)
    }
    private func cancel() {
        attempt = UUID(); completionRoute?.cancel(); completionRoute = nil
        touch.stop(); connecting = false; promptReady = false
    }
    private func contextChanged() {
        cancel(); connected = nil; notice = "Личность или настройки приглашения изменились. Повтори поиск."
    }
    private func connect(_ code: String) {
        guard visible, scenePhase == .active, !connecting, connected == nil,
              chat.activePersonaID == owner, chat.inviteCode == ownCode,
              SpyderChatEndpoint.normalized(chat.serverAddress) == server,
              code != ownCode else { return }
        connecting = true
        let run = attempt
        Task { @MainActor in
            let success = await chat.invite(code)
            guard visible, scenePhase == .active, run == attempt,
                  chat.activePersonaID == owner,
                  SpyderChatEndpoint.normalized(chat.serverAddress) == server else { return }
            connecting = false
            guard success, let person = chat.lastConnectedPerson else {
                notice = chat.errorMessage ?? "Не удалось создать чат. Проверь интернет и повтори подключение."
                return
            }
            peerAvatar = person.avatar
            connected = WalletContact(id: person.id, name: person.name,
                handle: person.username.map { "@" + $0 } ?? "", letter: String(person.name.prefix(1)), preview: "", time: "")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            completionRoute = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: reduceMotion ? 300_000_000 : 1_200_000_000) } catch { return }
                guard !Task.isCancelled, visible, run == attempt, scenePhase == .active,
                      chat.activePersonaID == owner else { return }
                routeToChat()
            }
            await chat.loadInviteSettings()
        }
    }
}
