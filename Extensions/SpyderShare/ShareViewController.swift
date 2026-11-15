import UIKit
import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication
import PDFKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let inputs = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem }.flatMap { $0.attachments ?? [] } ?? []
        let host = UIHostingController(rootView: SIDShareView(provider: inputs.first,
            close: { [weak self] in self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil) }))
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.topAnchor.constraint(equalTo: view.topAnchor),host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        host.didMove(toParent: self)
    }
}
private struct SIDShareView: View {
    let provider: NSItemProvider?
    let close: () -> Void
    @State private var record = SpyderIDRecord(kind: .notes)
    @State private var ready = false
    @State private var busy = false
    @State private var error: String?
    @State private var saved = false
    @Environment(\.scenePhase) private var phase
    @State private var generation = UUID()
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(sidText("Название", "Title"), text: $record.title)
                    if let name = record.fileName { Label(name, systemImage: "doc") }
                    TextEditor(text: $record.note).frame(minHeight: 100)
                }
                if let error { Text(error).foregroundStyle(.red) }
                if saved { Label(sidText("Сохранено в Spyder ID", "Saved in Spyder ID"), systemImage: "checkmark.circle") }
                else { Button(sidText("Подтвердить и сохранить", "Authenticate and save")) { Task { await save() } }.disabled(!ready || busy || record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                if busy { ProgressView() }
            }.navigationTitle("Spyder ID")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(saved ? sidText("Готово", "Done") : sidText("Отмена", "Cancel")) { generation = UUID(); close() } } }
        }.tint(.primary).privacySensitive().task { await read() }
        .overlay { if phase != .active { Color(uiColor: .systemBackground).ignoresSafeArea().overlay(Image(systemName: "lock.fill")) } }
        .onChange(of: phase) { _, phase in
            if phase == .background { generation = UUID(); record.fileData = nil; record.note = ""; ready = false; close() }
        }
    }
    @MainActor private func read() async {
        guard let provider else { error = sidText("Нет вложения.", "No attachment."); return }
        do {
            let type = provider.registeredTypeIdentifiers.first { id in
                guard let t = UTType(id) else { return false }; return t.conforms(to: .pdf) || t.conforms(to: .image)
            }
            if let type {
                let loaded: (Data, String) = try await withCheckedThrowingContinuation { continuation in
                    provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                        do {
                            if let error { throw error }; guard let url else { throw SpyderIDFailure.invalidRecord }
                            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size <= 10 * 1024 * 1024 else { throw SpyderIDFailure.tooLarge }
                            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                            let data = try handle.read(upToCount: 10 * 1024 * 1024 + 1) ?? Data()
                            guard data.count <= 10 * 1024 * 1024 else { throw SpyderIDFailure.tooLarge }
                            continuation.resume(returning: (data, url.lastPathComponent))
                        } catch { continuation.resume(throwing: error) }
                    }
                }
                guard PDFDocument(data: loaded.0) != nil || UIImage(data: loaded.0) != nil else { throw SpyderIDFailure.invalidRecord }
                record.kind = .documents; record.fileData = loaded.0; record.fileName = loaded.1
                record.title = provider.suggestedName ?? loaded.1
            } else {
                let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.plainText.identifier
                let text: String = try await withCheckedThrowingContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                        if let error { continuation.resume(throwing: error); return }
                        if let text = item as? String { continuation.resume(returning: text) }
                        else if let url = item as? URL { continuation.resume(returning: url.absoluteString) }
                        else { continuation.resume(throwing: SpyderIDFailure.invalidRecord) }
                    }
                }
                guard text.count <= 200000 else { throw SpyderIDFailure.tooLarge }
                record.note = text; record.title = sidText("Новая заметка", "New note")
            }
            ready = true
        } catch { self.error = error.localizedDescription }
    }
    @MainActor private func save() async {
        guard !busy else { return }; busy = true; error = nil; let token = generation; defer { busy = false }
        do {
            let auth = try await SpyderIDRepository.authenticate(); defer { auth.invalidate() }
            guard generation == token else { return }
            let key = try SpyderIDRepository.key(context: auth, allowCreate: false)
            try SpyderIDRepository.validate(record)
            _ = try SpyderIDRepository.mutate(key: key) { $0.append(record) }
            record.fileData = nil; record.note = ""; saved = true
        } catch { self.error = error.localizedDescription }
    }
}
