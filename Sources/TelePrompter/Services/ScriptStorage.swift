import Foundation

// MARK: - ScriptStorage
// Persists scripts to Application Support using JSON.

@MainActor
final class ScriptStorage: ObservableObject {

    @Published var scripts: [TeleprompterScript] = []

    private let storageURL: URL
    private var autosaveTask: Task<Void, Never>? = nil

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TelePrompter/Scripts", isDirectory: true)
        self.storageURL = dir

        try? FileManager.default.createDirectory(at: dir,
                                                  withIntermediateDirectories: true)
        load()
    }

    // MARK: - CRUD

    func create(title: String = "Untitled Script", content: String = "") -> TeleprompterScript {
        let script = TeleprompterScript(title: title, content: content)
        scripts.append(script)
        save(script)
        return script
    }

    func update(_ script: TeleprompterScript) {
        if let idx = scripts.firstIndex(where: { $0.id == script.id }) {
            scripts[idx] = script
        } else {
            scripts.append(script)
        }
        scheduleAutosave(script)
    }

    func delete(_ script: TeleprompterScript) {
        scripts.removeAll { $0.id == script.id }
        let file = storageURL.appendingPathComponent("\(script.id.uuidString).json")
        try? FileManager.default.removeItem(at: file)
    }

    func duplicate(_ script: TeleprompterScript) -> TeleprompterScript {
        var copy = script
        copy.id = UUID()
        copy.title = script.title + " Copy"
        copy.createdAt = Date()
        copy.modifiedAt = Date()
        scripts.append(copy)
        save(copy)
        return copy
    }

    // MARK: - Persistence

    func save(_ script: TeleprompterScript) {
        let file = storageURL.appendingPathComponent("\(script.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(script) {
            try? data.write(to: file, options: .atomic)
        }
    }

    private func scheduleAutosave(_ script: TeleprompterScript) {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 sec debounce
            guard !Task.isCancelled else { return }
            self?.save(script)
        }
    }

    private func load() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        scripts = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> TeleprompterScript? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(TeleprompterScript.self, from: data)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Crash recovery

    /// Saves a draft that can be recovered on next launch
    func saveDraft(_ content: String, scriptID: UUID) {
        let draftsURL = storageURL.deletingLastPathComponent().appendingPathComponent("Drafts")
        try? FileManager.default.createDirectory(at: draftsURL, withIntermediateDirectories: true)
        let draftFile = draftsURL.appendingPathComponent("\(scriptID.uuidString).draft.txt")
        try? content.write(to: draftFile, atomically: true, encoding: .utf8)
    }

    func recoverDraft(for scriptID: UUID) -> String? {
        let draftsURL = storageURL.deletingLastPathComponent().appendingPathComponent("Drafts")
        let draftFile = draftsURL.appendingPathComponent("\(scriptID.uuidString).draft.txt")
        return try? String(contentsOf: draftFile, encoding: .utf8)
    }

    func clearDraft(for scriptID: UUID) {
        let draftsURL = storageURL.deletingLastPathComponent().appendingPathComponent("Drafts")
        let draftFile = draftsURL.appendingPathComponent("\(scriptID.uuidString).draft.txt")
        try? FileManager.default.removeItem(at: draftFile)
    }
}
