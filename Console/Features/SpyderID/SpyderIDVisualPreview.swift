import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PDFKit
import AuthenticationServices

// Kept source-compatible with the stage-one WalletHomeView entry point.
struct SpyderIDPreviewEntry: View {
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Spyder ID").font(.title2.weight(.semibold))
                    Spacer()
                    Image(systemName: "lock").accessibilityHidden(true)
                }
                Text(sidText("Пароли, документы и заметки", "Passwords, documents and notes")).font(.subheadline)
                HStack {
                    Text(sidText("Открыть сейф", "Open vault"))
                    Spacer()
                    Image(systemName: "arrow.up.right").accessibilityHidden(true)
                }.font(.footnote.weight(.medium))
            }
            .padding(20).foregroundStyle(WalletTheme.contrast)
            .background(WalletTheme.ink, in: RoundedRectangle(cornerRadius: WalletTheme.cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: WalletTheme.cornerRadius))
        }.buttonStyle(.plain)
    }
}

struct SIDPrivacyShield: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content
            .accessibilityHidden(scenePhase != .active)
            .overlay {
                if scenePhase != .active {
                    WalletTheme.canvas.ignoresSafeArea()
                        .overlay(Image(systemName: "lock.fill").font(.largeTitle))
                }
            }
    }
}

private struct SIDPage<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24, content: content)
                .padding(WalletTheme.pageInset).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(WalletTheme.canvas).foregroundStyle(WalletTheme.ink)
    }
}

struct SpyderIDVisualPreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = SpyderIDStore()
    @State private var category: SpyderIDKind = .passwords
    @State private var query = ""
    @State private var path: [UUID] = []
    @State private var editor: SpyderIDRecord?
    @State private var settings = false
    private var matches: [SpyderIDRecord] {
        store.records.filter { $0.kind == category && (query.isEmpty ||
            ($0.title + " " + $0.website + " " + $0.username + " " + ($0.fileName ?? "") + " " + $0.note + " " + ($0.categoryLabel ?? "")).localizedCaseInsensitiveContains(query)) }
            .sorted { $0.modified > $1.modified }
    }
    var body: some View {
        NavigationStack(path: $path) {
            Group { if store.unlocked { vault } else { locked } }
                .navigationTitle("Spyder ID").navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: UUID.self) { id in SIDRecordView(id: id).environmentObject(store) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(sidText("Закрыть", "Close")) { store.lock(); dismiss() }
                    }
                    if store.unlocked {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { settings = true } label: {
                                Image(systemName: "slider.horizontal.3").frame(minWidth: 44, minHeight: 44)
                            }.accessibilityLabel(sidText("Настройки", "Settings"))
                        }
                    }
                }
        }
        .tint(WalletTheme.ink)
        .privacySensitive().modifier(SIDPrivacyShield())
        .sheet(item: $editor) { value in SIDEditView(initial: value).environmentObject(store) }
        .sheet(isPresented: $settings) { SIDSettingsView().environmentObject(store) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { reset() }
            else if phase == .active { store.reload() }
        }
        .onChange(of: store.unlocked) { _, unlocked in
            if !unlocked { path = []; editor = nil; settings = false; query = "" }
        }
        .onDisappear { store.lock() }
    }
    private func reset() { editor = nil; settings = false; path = []; query = ""; store.lock() }
    private var locked: some View {
        SIDPage {
            VStack(spacing: 20) {
                Image(systemName: "faceid").font(.system(size: 56)).accessibilityHidden(true)
                Text(sidText("Личный сейф", "Your personal vault")).font(.largeTitle.weight(.semibold))
                Text(sidText("Face ID или код-пароль устройства", "Face ID or device passcode"))
                    .foregroundStyle(WalletTheme.secondary)
                Button { Task { await store.unlock() } } label: {
                    if store.busy { ProgressView().tint(WalletTheme.contrast) }
                    else { Text(store.hasVault ? sidText("Открыть сейф", "Unlock vault") : sidText("Создать локальный сейф", "Create local vault")) }
                }.buttonStyle(SpyderActionButtonStyle()).disabled(store.busy)
                if let error = store.error { Text(error).foregroundStyle(.red).font(.footnote) }
            }.multilineTextAlignment(.center).padding(.vertical, 24)
            Label(sidText("Данные хранятся на устройстве. После создания сейфа экспортируйте зашифрованную копию и сохраните ключ восстановления отдельно.", "Data stays on this device. After creating a vault, export an encrypted backup and keep its recovery key separately."), systemImage: "iphone")
                .font(.footnote).foregroundStyle(WalletTheme.secondary)
        }
    }
    private var vault: some View {
        VStack(spacing: 0) {
            SIDPage {
                Text(sidText("Всё важное рядом", "Your essentials, together")).font(.largeTitle.weight(.semibold))
                TextField(sidText("Поиск по названию, сайту или логину", "Search by title, website or login"), text: $query)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                if matches.isEmpty {
                    ContentUnavailableView(query.isEmpty ? sidText("Здесь пока пусто", "Nothing here yet") : sidText("Ничего не найдено", "No results"), systemImage: category.symbol,
                        description: Text(query.isEmpty ? sidText("Добавьте первую запись в этот раздел.", "Add your first item to this section.") : sidText("Попробуйте другой запрос.", "Try another search.")))
                } else {
                    VStack(spacing: 0) {
                        ForEach(matches) { item in
                            NavigationLink(value: item.id) {
                                HStack(spacing: 14) {
                                    Image(systemName: item.passkey == nil ? item.kind.symbol : "person.badge.key.fill").frame(width: 44, height: 44)
                                        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title + (item.isDraft == true ? sidText(" · Черновик", " · Draft") : "")).font(.headline)
                                        Text(item.kind == .passwords ? (item.passkey == nil ? item.username : "Passkey · " + item.username) : (item.fileName ?? sidText("Личная заметка", "Personal note")))
                                            .font(.footnote).foregroundStyle(WalletTheme.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                                }.padding(.vertical, 14).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                Button(sidText("Добавить", "Add")) { editor = SpyderIDRecord(kind: category) }
                    .buttonStyle(SpyderActionButtonStyle())
            }
            HStack(spacing: 0) {
                ForEach(SpyderIDKind.allCases) { kind in
                    Button { category = kind; query = "" } label: {
                        VStack(spacing: 5) {
                            Image(systemName: kind.symbol).font(.title3)
                            Text(kind.title).font(.caption)
                        }.frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(category == kind ? WalletTheme.ink : WalletTheme.secondary)
                            .background(category == kind ? WalletTheme.surface : WalletTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(category == kind ? [.isSelected] : [])
                }
            }.padding(.horizontal, 12).padding(.vertical, 8).background(WalletTheme.canvas)
        }
    }
}

private struct SIDEditView: View {
    @EnvironmentObject private var store: SpyderIDStore
    @Environment(\.dismiss) private var dismiss
    @State private var value: SpyderIDRecord
    @State private var importer = false
    @State private var error: String?
    @State private var assistantDescription = ""
    @State private var proposedTitle: String?
    @State private var proposedCategory: String?
    @State private var consent = false
    @State private var processing = false
    @AppStorage("spyder.id.gemini.model") private var model = "gemini-3.5-flash"
    init(initial: SpyderIDRecord) { _value = State(initialValue: initial) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(sidText("Название", "Title"), text: $value.title)
                    if let passkey = value.passkey {
                        Label("Passkey", systemImage: "person.badge.key.fill")
                        Text(passkey.relyingParty)
                        Text(value.username)
                        Text(sidText("Ключ и привязку к сайту нельзя изменять вручную.", "The key and website binding cannot be edited manually.")).font(.footnote)
                    } else if value.kind == .passwords {
                        TextField(sidText("Сайт", "Website"), text: $value.website)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField(sidText("Логин", "Username"), text: $value.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField(sidText("Пароль", "Password"), text: $value.password).textContentType(.newPassword)
                        Button(sidText("Создать надёжный пароль", "Generate a strong password")) {
                            do { value.password = try SpyderIDCodec.password() } catch { self.error = error.localizedDescription }
                        }
                    } else if value.kind == .documents {
                        if let name = value.fileName { Label(name, systemImage: "doc") }
                        TextField(sidText("Категория", "Category"), text: Binding(get: { value.categoryLabel ?? "" }, set: { value.categoryLabel = $0 }))
                        Button(sidText("Выбрать PDF или изображение", "Choose PDF or image")) { importer = true }
                        Text(sidText("Не больше 10 МБ. Файл будет зашифрован внутри сейфа.", "Up to 10 MB. The file will be encrypted inside the vault."))
                            .font(.footnote).foregroundStyle(WalletTheme.secondary)
                    }
                }
                Section(sidText("Заметка", "Note")) {
                    TextEditor(text: $value.note).frame(minHeight: 120)
                        .autocorrectionDisabled().accessibilityLabel(sidText("Текст заметки", "Note text"))
                }
                if value.kind == .documents {
                    Section(sidText("Помощник", "Assistant")) {
                        Button(sidText("Распознать текст на устройстве", "Recognize text on device")) {
                            guard let data = value.fileData else { return }; processing = true
                            Task { @MainActor in
                                defer { processing = false }
                                do {
                                    let text = try await SIDAssistant.extract(data)
                                    guard store.unlocked else { return }
                                    if text.isEmpty { error = sidText("Текст не найден. Документ можно сохранить без распознавания.", "No text found. You can save the document without recognition.") }
                                    else { value.note = String((value.note + "\n" + text).prefix(200000)) }
                                } catch { self.error = error.localizedDescription }
                            }
                        }.disabled(processing || value.fileData == nil)
                        TextField(sidText("Описание для Gemini, без личных данных", "Description for Gemini, no personal data"), text: $assistantDescription, axis: .vertical)
                        Button(sidText("Предложить название через Gemini", "Suggest a title with Gemini")) { consent = true }
                            .disabled(processing || assistantDescription.isEmpty)
                        if processing { ProgressView() }
                        if let title = proposedTitle, let category = proposedCategory {
                            Text(title).font(.headline); Text(category)
                            Button(sidText("Применить предложение", "Apply suggestion")) { value.title = title; value.categoryLabel = category; proposedTitle = nil; proposedCategory = nil }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button(sidText("Сохранить", "Save")) {
                        do { try store.save(value); dismiss() } catch { self.error = error.localizedDescription }
                    }.disabled(!store.unlocked)
                }
            }
            .navigationTitle(value.kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(sidText("Отмена", "Cancel")) { dismiss() } } }
        }.tint(WalletTheme.ink).privacySensitive().modifier(SIDPrivacyShield())
        .confirmationDialog(sidText("Отправить только введённое описание в Google Gemini?", "Send only the entered description to Google Gemini?"), isPresented: $consent, titleVisibility: .visible) {
            Button(sidText("Отправить описание", "Send description")) {
                processing = true; error = nil
                Task { @MainActor in
                    defer { processing = false }
                    do {
                        let suggestion = try await SIDAssistant.suggest(description: assistantDescription, model: model)
                        guard store.unlocked else { return }
                        proposedTitle = suggestion.title; proposedCategory = suggestion.category
                    } catch { self.error = sidText("Gemini недоступен. Проверьте API-ключ, модель и сеть. Документ не изменён.", "Gemini is unavailable. Check the API key, model and network. Document was not changed.") }
                }
            }
            Button(sidText("Отмена", "Cancel"), role: .cancel) {}
        } message: { Text(assistantDescription) }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.pdf, .image]) { result in
            guard store.unlocked else { return }
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 10 * 1024 * 1024 else { throw SpyderIDFailure.tooLarge }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 10 * 1024 * 1024 + 1) ?? Data()
                guard data.count <= 10 * 1024 * 1024 else { throw SpyderIDFailure.tooLarge }
                guard PDFDocument(data: data) != nil || UIImage(data: data) != nil else { throw SpyderIDFailure.invalidRecord }
                value.fileData = data; value.fileName = url.lastPathComponent
                if value.title.isEmpty { value.title = url.deletingPathExtension().lastPathComponent }
                error = nil
            } catch { self.error = error.localizedDescription }
        }
        .onChange(of: store.unlocked) { _, unlocked in if !unlocked { value = SpyderIDRecord(kind: value.kind); assistantDescription = ""; proposedTitle = nil; proposedCategory = nil; dismiss() } }
    }
}

private struct SIDRecordView: View {
    let id: UUID
    @EnvironmentObject private var store: SpyderIDStore
    @Environment(\.dismiss) private var dismiss
    @State private var reveal = false
    @State private var editing: SpyderIDRecord?
    @State private var deleting = false
    @State private var message: String?
    @State private var exportDocument: SIDTransferDocument?
    @State private var exporting = false
    private var record: SpyderIDRecord? { store.records.first { $0.id == id } }
    var body: some View {
        SIDPage {
            if let record {
                Label(record.title, systemImage: record.kind.symbol).font(.title.weight(.semibold))
                if let passkey = record.passkey {
                    WalletCard {
                        VStack(alignment: .leading, spacing: 18) {
                            Label("Passkey", systemImage: "person.badge.key.fill")
                            detail(sidText("Сайт", "Website"), passkey.relyingParty)
                            detail(sidText("Аккаунт", "Account"), record.username)
                            Text(sidText("Выберите Spyder ID в системном окне входа на этом сайте. Сам ключ не нужно копировать.", "Choose Spyder ID in the system sign-in sheet on this website. You do not need to copy the key."))
                            Text(passkey.backedUp ? sidText("Ключ включён в экспортированную или восстановленную копию.", "This key was exported or restored in an encrypted backup.") : sidText("Создайте зашифрованную резервную копию, чтобы не потерять доступ при смене телефона.", "Create an encrypted backup to preserve access when changing phones."))
                                .font(.footnote).foregroundStyle(WalletTheme.secondary)
                        }
                    }
                } else if record.kind == .passwords {
                    WalletCard {
                        VStack(alignment: .leading, spacing: 18) {
                            detail(sidText("Сайт", "Website"), record.website)
                            Divider()
                            detail(sidText("Логин", "Username"), record.username)
                            Divider()
                            HStack {
                                detail(sidText("Пароль", "Password"), reveal ? record.password : "••••••••••••")
                                Spacer()
                                Button { reveal.toggle() } label: {
                                    Image(systemName: reveal ? "eye.slash" : "eye").frame(minWidth: 44, minHeight: 44)
                                }.accessibilityLabel(sidText("Показать или скрыть пароль", "Show or hide password"))
                            }
                        }
                    }
                    Button(sidText("Копировать пароль", "Copy password")) { copy(record.password) }
                        .buttonStyle(SpyderActionButtonStyle())
                    Button(sidText("Копировать логин", "Copy username")) { copy(record.username) }
                        .buttonStyle(SpyderActionButtonStyle(.secondary))
                }
                if record.isDraft == true {
                    Text(sidText("Этот пароль создан в Safari. Убедитесь, что регистрация завершена, затем подтвердите сохранение.", "This password was created in Safari. Check that registration completed, then confirm saving."))
                        .font(.footnote).foregroundStyle(WalletTheme.secondary)
                    Button(sidText("Подтвердить сохранение", "Confirm saving")) {
                        var confirmed = record; confirmed.isDraft = false
                        do { try store.save(confirmed) } catch { message = error.localizedDescription }
                    }.buttonStyle(SpyderActionButtonStyle(.secondary))
                }
                if let data = record.fileData {
                    if PDFDocument(data: data) != nil {
                        SIDPDFView(data: data).frame(height: 420).clipShape(RoundedRectangle(cornerRadius: 16))
                    } else if let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(record.title)
                    }
                    Text(record.fileName ?? "").font(.footnote).foregroundStyle(WalletTheme.secondary)
                    Button(sidText("Экспортировать документ", "Export document")) {
                        exportDocument = SIDTransferDocument(data: data); exporting = true
                    }.buttonStyle(SpyderActionButtonStyle(.secondary))
                    Text(sidText("Экспортируемая копия не зашифрована сейфом. Вы сами выбираете место сохранения.", "The exported copy is not vault-encrypted. You choose its destination."))
                        .font(.footnote).foregroundStyle(WalletTheme.secondary)
                }
                if !record.note.isEmpty { WalletCard { Text(record.note).frame(maxWidth: .infinity, alignment: .leading) } }
                if let message { Text(message).font(.footnote).foregroundStyle(WalletTheme.secondary).accessibilityAddTraits(.updatesFrequently) }
                Button(sidText("Изменить", "Edit")) { editing = record }.buttonStyle(SpyderActionButtonStyle(.secondary))
                Button(sidText("Удалить запись", "Delete item"), role: .destructive) { deleting = true }
                    .frame(minHeight: 44)
            }
        }.navigationTitle(sidText("Запись", "Item")).navigationBarTitleDisplayMode(.inline)
        .privacySensitive().modifier(SIDPrivacyShield())
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .data, defaultFilename: record?.fileName ?? "document") { result in
            exportDocument = nil
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .sheet(item: $editing) { SIDEditView(initial: $0).environmentObject(store) }
        .confirmationDialog(sidText("Удалить без возможности восстановления?", "Delete permanently?"), isPresented: $deleting, titleVisibility: .visible) {
            Button(sidText("Удалить", "Delete"), role: .destructive) {
                do { try store.delete(id); dismiss() } catch { message = error.localizedDescription }
            }
            Button(sidText("Отмена", "Cancel"), role: .cancel) {}
        }
        .onChange(of: store.unlocked) { _, unlocked in if !unlocked { reveal = false; editing = nil; deleting = false; exportDocument = nil; exporting = false } }
    }
    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.footnote).foregroundStyle(WalletTheme.secondary)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func copy(_ text: String) {
        guard store.unlocked else { return }
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: text]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(30)])
        message = sidText("Скопировано на 30 секунд. Передача на другие устройства отключена.", "Copied for 30 seconds. Cross-device clipboard is disabled.")
    }
}

private struct SIDPDFView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.document = PDFDocument(data: data)
        return view
    }
    final class Coordinator { var data: Data? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func updateUIView(_ uiView: PDFView, context: Context) {
        if context.coordinator.data != data {
            context.coordinator.data = data
            uiView.document = PDFDocument(data: data)
        }
    }
    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        uiView.document = nil; coordinator.data = nil
    }
}

private struct SIDSettingsView: View {
    @EnvironmentObject private var store: SpyderIDStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            SIDPage {
                Text(sidText("Защита и доступ", "Protection and access")).font(.largeTitle.weight(.semibold))
                WalletCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(sidText("Face ID / код-пароль устройства", "Face ID / device passcode"), systemImage: "faceid")
                        Divider()
                        Label(sidText("Блокировка при уходе в фон", "Lock when app enters background"), systemImage: "lock")
                        Divider()
                        Label(sidText("Зашифрованное хранение на устройстве", "Encrypted on-device storage"), systemImage: "iphone")
                    }
                }
                NavigationLink(sidText("Резервная копия и восстановление", "Backup and restore")) { SIDBackupView().environmentObject(store) }
                    .frame(minHeight: 44)
                NavigationLink(sidText("Помощник для документов", "Document assistant")) { SIDAssistantSettings() }
                    .frame(minHeight: 44)
                WalletCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(sidText("Автозаполнение и Safari", "AutoFill and Safari")).font(.headline)
                        Text(sidText("В настройках iPhone включите Spyder ID как источник автозаполнения. В Safari включите расширение Spyder ID и разрешите доступ к нужному сайту. Вызывайте его через меню расширений браузера.", "Enable Spyder ID as an AutoFill provider in iPhone Settings. Enable the Spyder ID Safari extension and allow it on the website. Open it from the browser extensions menu."))
                            .font(.footnote).foregroundStyle(WalletTheme.secondary)
                        Text(sidText("Для создания passkey откройте настройки безопасности аккаунта на сайте, нажмите «Создать ключ входа» и выберите Spyder ID в системном окне iOS.", "To create a passkey, open the website account security settings, choose Create passkey, then select Spyder ID in the iOS system sheet.")).font(.footnote).foregroundStyle(WalletTheme.secondary)
                        Button(sidText("Обновить подсказки аккаунтов", "Refresh account suggestions")) { store.reload() }
                    }
                }
                Button(sidText("Заблокировать сейф", "Lock vault")) { store.lock(); dismiss() }
                    .buttonStyle(SpyderActionButtonStyle())
            }.navigationTitle(sidText("Настройки", "Settings"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(sidText("Закрыть", "Close")) { dismiss() } } }
        }.tint(WalletTheme.ink)
    }
}
