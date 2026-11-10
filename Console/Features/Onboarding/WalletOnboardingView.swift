import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum SetupStep { case start, backup, verify, importWallet, complete }

struct WalletOnboardingView: View {
    @EnvironmentObject private var access: WalletAccess
    @Environment(\.dismiss) private var dismiss
    private let isAddingAccount: Bool
    private let onComplete: (() -> Void)?

    init(isAddingAccount: Bool = false, onComplete: (() -> Void)? = nil) {
        self.isAddingAccount = isAddingAccount
        self.onComplete = onComplete
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var step: SetupStep = .start
    @State private var phrase = ""
    @State private var importText = ""
    @State private var answers = ["", "", ""]
    @State private var confirmOffline = false
    @State private var reveal = false
    @State private var testPhraseOnly = false
    @State private var showCopyWarning = false
    @State private var cloudSaved = false
    @State private var cloudBusy = false
    @State private var cloudInfo: String?
    @State private var cloudFailure: String?

    @FocusState private var focusedImport: Bool
    private let positions = [1, 5, 10] // 1-based; never the whole secret in an alert or log

    private var words: [String] { phrase.split(separator: " ").map(String.init) }
    private var isVerified: Bool {
        words.count == 12 && positions.enumerated().allSatisfy { index, position in
            answers[index].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == words[position - 1]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if step != .start && step != .complete {
                    SpyderNavigationButton(symbol: "chevron.left", label: "Назад") { goBack() }
                } else if step == .start && isAddingAccount {
                    SpyderNavigationButton(symbol: "xmark", label: "Закрыть") { dismiss() }
                }
                Text(verbatim: "Spyder Wallet")
                    .font(.headline)
                Spacer()
                switch step {
                case .backup: stepLabel("01 / 02")
                case .verify: stepLabel("02 / 02")
                default: EmptyView()
                }
            }
            .foregroundStyle(WalletTheme.ink)
            .frame(minHeight: 48)
            .padding(.horizontal, 20)
            Divider()

            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch step {
                        case .start: welcome
                        case .backup: backup
                        case .verify: verification
                        case .importWallet: importFlow
                        case .complete: completion
                        }
                    }
                    .frame(minHeight: step == .start ? max(0, viewport.size.height - 48) : nil, alignment: .top)
                    .frame(maxWidth: 540)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .top)
                }
                .scrollDismissesKeyboard(.interactively)
                .id(step)
            }
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.27), value: step)
        .alert("Безопасность кошелька", isPresented: Binding(
            get: { access.errorMessage != nil },
            set: { if !$0 { access.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { access.errorMessage = nil }
        } message: { Text(access.errorMessage ?? "") }
        .confirmationDialog("Копирование секретной фразы", isPresented: $showCopyWarning, titleVisibility: .visible) {
            Button("Скопировать на 45 секунд") {
                UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: phrase]], options: [
                    .expirationDate: Date().addingTimeInterval(45), .localOnly: true
                ])
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        } message: {
            Text("Другие приложения могут прочитать буфер обмена. Предпочтительнее записать слова офлайн.")
        }
        .alert("iCloud Keychain", isPresented: Binding(get: { cloudFailure != nil }, set: { if !$0 { cloudFailure = nil } })) {
            Button("Понятно", role: .cancel) { cloudFailure = nil }
        } message: { Text(cloudFailure ?? "") }
        .overlay {
            if scenePhase != .active && (step == .backup || step == .verify || step == .importWallet) {
                WalletTheme.canvas.ignoresSafeArea()
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 16)
            Image("SpyderLaunchLogo")
                .resizable().scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("Ваш кошелёк.\nВаши ключи.")
                .font(.largeTitle.bold())
                .foregroundStyle(WalletTheme.ink)
                .padding(.top, 24)
                .accessibilityAddTraits(.isHeader)
            Text("Все криптоактивы и контакты — в одном пространстве. Только ты контролируешь доступ к своему кошельку.")
                .font(.body)
                .foregroundStyle(WalletTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Spacer(minLength: 44)
            VStack(spacing: 8) {
                Button { create() } label: { Text("Создать кошелёк").spyderPrimaryButton() }
                Button { step = .importWallet } label: {
                    Text("У меня уже есть кошелёк")
                        .font(.headline)
                        .foregroundStyle(WalletTheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                Label("Ключи хранятся в защищённом хранилище iPhone", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(WalletTheme.secondary)
                    .padding(.top, 8)
            }
            .buttonStyle(.plain)
        }
    }

    private var backup: some View {
        VStack(alignment: .leading, spacing: 19) {
            heading("Сохрани 12 слов", subtitle: "Это единственный способ восстановить кошелёк при потере устройства. Запиши их на бумаге в правильном порядке.")
            WalletCard {
                VStack(spacing: 14) {
                    HStack {
                        Label("Фраза восстановления", systemImage: "key.horizontal")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: reveal ? "eye" : "eye.slash")
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(WalletTheme.ink)
                    if reveal {
                        wordGrid(words)
                            .transition(.opacity)
                            .privacySensitive()
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 28))
                            Text("Слова скрыты")
                                .font(.system(size: 14))
                        }
                        .foregroundStyle(WalletTheme.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                    }
                    Button(reveal ? "Скрыть слова" : "Показать слова") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { reveal.toggle() }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WalletTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            if reveal {
                Button { showCopyWarning = true } label: {
                    Label("Копировать слова (45 секунд)", systemImage: "doc.on.doc")
                        .font(.system(size: 14, weight: .medium))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            Label("Никому не отправляй фразу. Скриншоты и обычные заметки не защищают твои средства.", systemImage: "exclamationmark.shield")
                .font(.footnote)
                .foregroundStyle(WalletTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { confirmOffline.toggle() } label: {
                HStack(spacing: 12) {
                    Image(systemName: confirmOffline ? "checkmark.square.fill" : "square")
                        .font(.title3)
                    Text("Подтверждаю: 12 слов записаны офлайн")
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(WalletTheme.ink)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Подтверждаю, что записал 12 слов офлайн")
            .accessibilityValue(confirmOffline ? "Подтверждено" : "Не подтверждено")
            .accessibilityHint("Нужно подтвердить, чтобы перейти к проверке трёх слов")
            Button { reveal = false; step = .verify } label: {
                Text("Продолжить").spyderPrimaryButton()
            }
            .disabled(!confirmOffline)
            .opacity(confirmOffline ? 1 : 0.45)
            .buttonStyle(.plain)
        }
    }

    private var verification: some View {
        VStack(alignment: .leading, spacing: 19) {
            heading("Проверим запись", subtitle: "Введи три слова по их номерам. Так мы убедимся, что фраза сохранена правильно.")
            ForEach(0..<positions.count, id: \.self) { index in
                WalletCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Слово №\(positions[index])")
                            .font(.footnote)
                            .foregroundStyle(WalletTheme.secondary)
                        SecureField("Введите слово", text: $answers[index])
                            .font(.body.weight(.medium))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textContentType(.password)
                            .privacySensitive()
                    }
                }
            }
            Text("Проверь написание слов на английском. Spyder не получает и не сохраняет их на сервере.")
                .font(.footnote)
                .foregroundStyle(WalletTheme.secondary)
            Button {
                guard isVerified else { return }
                if access.savePhrase(phrase) {
                    phrase = ""
                    answers = ["", "", ""]
                    step = .complete
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } label: { Text("Создать защищённый кошелёк").spyderPrimaryButton() }
            .buttonStyle(.plain)
            .disabled(!isVerified)
            .opacity(isVerified ? 1 : 0.45)
        }
    }

    private var importFlow: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Восстановить кошелёк", subtitle: "Вставь 12 или 24 слова восстановления в исходном порядке.")
            Button { restoreFromICloud() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "icloud.and.arrow.down")
                        .symbolEffect(.pulse, isActive: cloudBusy)
                    Text(LocalizedStringKey(cloudBusy ? "Проверяем iCloud Keychain…" : "Восстановить из iCloud Keychain"))
                }
                .spyderPrimaryButton()
            }
            .buttonStyle(.plain)
            .disabled(cloudBusy)
            Text("Требуется тот же Apple Account и включённый iCloud Keychain. Если резервной копии нет, используй свои 12/24 слова.")
                .font(.footnote).foregroundStyle(WalletTheme.secondary)
            WalletCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Фраза восстановления")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WalletTheme.secondary)
                    SecureField("12 или 24 слова, через пробел", text: $importText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textContentType(.password)
                        .focused($focusedImport)
                        .font(.body)
                        .foregroundStyle(WalletTheme.ink)
                        .privacySensitive()
                }
            }
            Button {
                // Explicit user action: Apple controls whether pasteboard access is allowed.
                if let text = UIPasteboard.general.string { importText = text }
            } label: {
                Label("Вставить из буфера обмена", systemImage: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            Label("Если у старого кошелька был дополнительный пароль к фразе восстановления, этот способ импорта пока не поддерживается.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(WalletTheme.secondary)
            Text("Тестовая версия не прошла аудит. Не вводите фразу от кошелька с реальными средствами.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WalletTheme.ink)
            Button { testPhraseOnly.toggle() } label: {
                HStack(spacing: 12) {
                    Image(systemName: testPhraseOnly ? "checkmark.square.fill" : "square")
                        .font(.title3)
                    Text("Подтверждаю: это тестовый кошелёк без реальных средств")
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(WalletTheme.ink)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Подтверждаю, что фраза от тестового кошелька")
            .accessibilityValue(testPhraseOnly ? "Подтверждено" : "Не подтверждено")
            .accessibilityHint("Импорт кошелька с реальными средствами в этой тестовой версии запрещён")
            Button {
                focusedImport = false
                do {
                    let normalized = try WalletVault.canonicalPhrase(importText)
                    if access.savePhrase(normalized) {
                        importText = ""
                        step = .complete
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                } catch { access.errorMessage = error.localizedDescription }
            } label: { Text("Импортировать кошелёк").spyderPrimaryButton() }
            .buttonStyle(.plain)
            .disabled(!testPhraseOnly || importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var completion: some View {
        VStack(alignment: .center, spacing: 17) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(WalletTheme.ink)
                .symbolEffect(.bounce, value: step == .complete)
            Text("Кошелёк защищён")
                .font(.title.bold())
                .foregroundStyle(WalletTheme.ink)
            Text("Фраза сохранена локально в защищённом Keychain iPhone. Face ID или код устройства защищает доступ. Для восстановления после потери телефона сохрани резервную копию отдельно.")
                .font(.body)
                .foregroundStyle(WalletTheme.secondary)
                .multilineTextAlignment(.center)
            WalletCard {
                VStack(alignment: .leading, spacing: 11) {
                    Label("Резервная копия в iCloud Keychain", systemImage: "icloud.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Необязательно. Фраза синхронизируется только через iCloud Keychain Apple, если он включён. Это отличается от локальной защиты и позволяет восстановить кошелёк на другом iPhone. Никогда не заменяй этим офлайн-копию.")
                        .font(.footnote)
                        .foregroundStyle(WalletTheme.secondary)
                    if cloudSaved {
                        Label("Копия добавлена в iCloud Keychain", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            cloudBusy = true
                            let selectedID = access.activeWalletID
                            Task.detached(priority: .userInitiated) {
                                do {
                                    let words = try WalletVault.revealForBackup(id: selectedID)
                                    try WalletICloudRecovery.saveWithConsent(words.joined(separator: " "))
                                    await MainActor.run { cloudSaved = true; cloudBusy = false }
                                } catch {
                                    await MainActor.run { cloudFailure = error.localizedDescription; cloudBusy = false }
                                }
                            }
                        } label: {
                            Label(LocalizedStringKey(cloudBusy ? "Сохраняем…" : "Сохранить по моему согласию"), systemImage: "icloud")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .disabled(cloudBusy)
                    }
                }
            }
            Button {
                access.finishSetup()
                onComplete?()
            } label: {
                Text("Открыть Spyder Wallet").spyderPrimaryButton()
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    @ViewBuilder private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(title)).font(.largeTitle.bold()).foregroundStyle(WalletTheme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(LocalizedStringKey(subtitle)).font(.body).foregroundStyle(WalletTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepLabel(_ text: String) -> some View {
        Text(text).font(.caption.monospacedDigit())
            .tracking(1).foregroundStyle(WalletTheme.secondary)
    }

    private func wordGrid(_ words: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                HStack(spacing: 8) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(.footnote, design: .monospaced, weight: .medium))
                        .foregroundStyle(WalletTheme.secondary)
                    Text(word)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(WalletTheme.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11).padding(.vertical, 12)
                .background(WalletTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func restoreFromICloud() {
        guard !cloudBusy else { return }
        cloudBusy = true
        Task.detached(priority: .userInitiated) {
            do {
                let recovered = try WalletICloudRecovery.restore()
                await MainActor.run {
                    cloudBusy = false
                    if access.savePhrase(recovered) {
                        importText = ""
                        step = .complete
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            } catch {
                await MainActor.run { cloudBusy = false; cloudFailure = error.localizedDescription }
            }
        }
    }

    private func create() {
        do {
            phrase = try WalletVault.makeNewPhrase()
            answers = ["", "", ""]
            confirmOffline = false
            reveal = false
            step = .backup
        } catch { access.errorMessage = error.localizedDescription }
    }

    private func goBack() {
        switch step {
        case .backup:
            phrase = ""
            reveal = false
            confirmOffline = false
            step = .start
        case .verify:
            answers = ["", "", ""]
            step = .backup
        case .importWallet:
            importText = ""
            testPhraseOnly = false
            step = .start
        case .start, .complete: break
        }
    }
}

struct WalletUnlockView: View {
    @EnvironmentObject private var access: WalletAccess

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image("SpyderLaunchLogo")
                .resizable().scaledToFit()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)
                .spyderReveal(0.05)
            Text("Spyder Wallet")
                .font(.title.bold())
                .foregroundStyle(WalletTheme.ink)
            Text("Ваш кошелёк заблокирован")
                .font(.body)
                .foregroundStyle(WalletTheme.secondary)
            Spacer()
            Button { access.unlock() } label: {
                Label("Разблокировать", systemImage: "faceid")
                    .spyderPrimaryButton()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.bottom, 25)
        }
        .frame(maxWidth: .infinity)
        .background(WalletTheme.canvas.ignoresSafeArea())
        .alert("Не удалось разблокировать", isPresented: Binding(
            get: { access.errorMessage != nil },
            set: { if !$0 { access.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { access.errorMessage = nil }
        } message: { Text(access.errorMessage ?? "") }
    }
}
