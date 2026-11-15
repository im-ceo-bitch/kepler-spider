import SwiftUI
import UniformTypeIdentifiers

struct SIDTransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw SpyderIDFailure.invalidRecord }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SIDBackupView: View {
    @EnvironmentObject private var store: SpyderIDStore
    @State private var document: SIDTransferDocument?
    @State private var recovery = ""
    @State private var exporting = false
    @State private var importing = false
    @State private var restoreData: Data?
    @State private var importKey = ""
    @State private var confirmRestore = false
    @State private var message: String?
    var body: some View {
        Form {
            Section(sidText("Создать резервную копию", "Create backup")) {
                Text(sidText("Копия зашифрована отдельным случайным ключом. Для восстановления нужны и файл, и ключ. Храните их отдельно.", "The backup is encrypted with a separate random key. Both the file and key are required to restore. Keep them separately."))
                Button(sidText("Подготовить копию", "Prepare backup")) {
                    do {
                        let result = try store.backup()
                        document = SIDTransferDocument(data: result.data); recovery = result.recovery; message = nil
                    } catch { message = error.localizedDescription }
                }
                if !recovery.isEmpty {
                    Text(sidText("Ключ восстановления", "Recovery key")).font(.headline)
                    Text(recovery).font(.body.monospaced()).textSelection(.enabled)
                    Button(sidText("Ключ сохранён отдельно — экспортировать файл", "Key saved separately — export file")) { exporting = true }
                }
            }
            Section(sidText("Восстановить из файла", "Restore from file")) {
                Text(sidText("Записи будут добавлены. Существующие данные не перезаписываются; конфликтующие записи сохраняются отдельными копиями.", "Items will be added. Existing data is not overwritten; conflicting items are added as separate copies."))
                SecureField(sidText("Ключ восстановления", "Recovery key"), text: $importKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(sidText("Выбрать зашифрованную копию", "Choose encrypted backup")) { importing = true }
                    .disabled(importKey.isEmpty)
            }
            if let message { Section { Text(message) } }
        }
        .navigationTitle(sidText("Резервная копия", "Backup"))
        .privacySensitive().modifier(SIDPrivacyShield())
        .fileExporter(isPresented: $exporting, document: document, contentType: .data, defaultFilename: "Spyder-ID-backup.spyderid") { result in
            switch result {
            case .success: message = sidText("Зашифрованная копия экспортирована. Убедитесь, что ключ сохранён отдельно.", "Encrypted backup exported. Check that the key is saved separately.")
            case .failure(let error): message = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            guard store.unlocked else { return }
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                let bytes = try handle.read(upToCount: 31 * 1024 * 1024 + 1) ?? Data()
                guard bytes.count <= 31 * 1024 * 1024 else { throw SpyderIDFailure.tooLarge }
                restoreData = bytes; confirmRestore = true
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog(sidText("Добавить записи из резервной копии?", "Add items from this backup?"), isPresented: $confirmRestore, titleVisibility: .visible) {
            Button(sidText("Восстановить", "Restore")) {
                do {
                    guard let data = restoreData else { return }
                    let count = try store.restore(data, recovery: importKey)
                    message = sidText("Копия прочитана. Записей: ", "Backup read. Items: ") + String(count)
                    restoreData = nil; importKey = ""
                } catch { message = sidText("Не удалось восстановить: проверьте файл и ключ. Сейф не изменён.", "Restore failed: check the file and key. Vault was not changed.") }
            }
            Button(sidText("Отмена", "Cancel"), role: .cancel) { restoreData = nil }
        }
        .onChange(of: store.unlocked) { _, open in
            if !open { document = nil; recovery = ""; importKey = ""; restoreData = nil; exporting = false; importing = false }
        }
    }
}
