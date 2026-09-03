import SwiftUI
import UniformTypeIdentifiers

// MARK: - ScriptLibraryView

struct ScriptLibraryView: View {
    @EnvironmentObject var storage: ScriptStorage
    @EnvironmentObject var state: TeleprompterState
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var sessionController: SessionController

    @State private var selectedScriptID: UUID? = nil
    @State private var showImportPicker: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var scriptToDelete: TeleprompterScript? = nil
    @State private var importError: String? = nil
    @State private var showImportError: Bool = false
    @State private var showNewScriptSheet: Bool = false
    @State private var newScriptTitle: String = ""
    @State private var renameScript: TeleprompterScript? = nil
    @State private var renameTitle: String = ""

    var body: some View {
        HSplitView {
            // Script list
            scriptList
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 320)

            // Editor
            if let id = selectedScriptID,
               storage.scripts.contains(where: { $0.id == id }) {
                ScriptEditorView(scriptID: id)
                    .id(id)
            } else {
                emptyState
            }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.plainText, .pdf, UTType(filenameExtension: "md") ?? .plainText,
                                   UTType(filenameExtension: "markdown") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Import Error", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Unknown error")
        }
        .sheet(isPresented: $showNewScriptSheet) {
            newScriptSheet
        }
        .sheet(item: $renameScript) { script in
            renameSheet(script: script)
        }
        .alert("Delete Script", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let s = scriptToDelete { storage.delete(s) }
                scriptToDelete = nil
                selectedScriptID = nil
            }
            Button("Cancel", role: .cancel) { scriptToDelete = nil }
        } message: {
            Text("Are you sure you want to delete \"\(scriptToDelete?.title ?? "this script")\"? This cannot be undone.")
        }
    }

    // MARK: - Script list

    private var scriptList: some View {
        VStack(spacing: 0) {
            // List header toolbar
            HStack {
                Text("Scripts")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("New Script") { showNewScriptSheet = true }
                    Button("Import File…") { showImportPicker = true }
                    Button("Use Test Script") { loadTestScript() }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if storage.scripts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No scripts yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Create a Script") { showNewScriptSheet = true }
                    Button("Import a File") { showImportPicker = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(selection: $selectedScriptID) {
                    ForEach(storage.scripts) { script in
                        scriptRow(script)
                            .tag(script.id)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                }
                .listStyle(.sidebar)
                // Single-click opens in editor (selection binding). Double-click loads.
                // Use onChange + keyboard/context for load — do NOT put TapGesture on rows
                // (that steals List selection and forces 2–3 clicks).
            }
        }
    }

    private func scriptRow(_ script: TeleprompterScript) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(script.title)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(script.wordCount) words")
                    Text("·")
                    Text(durationText(script))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()

            if state.loadedScript?.id == script.id {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    .help("Loaded in teleprompter")
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Open in Editor") { selectedScriptID = script.id }
            Button("Load in Teleprompter") { loadScript(script) }
            Divider()
            Button("Rename…") {
                renameScript = script
                renameTitle = script.title
            }
            Button("Duplicate") { _ = storage.duplicate(script) }
            Divider()
            Button("Delete", role: .destructive) {
                scriptToDelete = script
                showDeleteConfirm = true
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select a script to edit")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Or create a new one to get started.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                Button("New Script") { showNewScriptSheet = true }
                    .buttonStyle(.borderedProminent)
                Button("Import File…") { showImportPicker = true }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - New script sheet

    private var newScriptSheet: some View {
        VStack(spacing: 16) {
            Text("New Script")
                .font(.headline)
            TextField("Script title", text: $newScriptTitle)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            HStack {
                Button("Cancel") {
                    showNewScriptSheet = false
                    newScriptTitle = ""
                }
                Button("Create") {
                    let title = newScriptTitle.isEmpty ? "Untitled Script" : newScriptTitle
                    let script = storage.create(title: title)
                    selectedScriptID = script.id
                    showNewScriptSheet = false
                    newScriptTitle = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(false)
            }
        }
        .padding(24)
        .frame(width: 340)
    }

    // MARK: - Rename sheet

    private func renameSheet(script: TeleprompterScript) -> some View {
        VStack(spacing: 16) {
            Text("Rename Script")
                .font(.headline)
            TextField("Script title", text: $renameTitle)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            HStack {
                Button("Cancel") { renameScript = nil }
                Button("Rename") {
                    if let idx = storage.scripts.firstIndex(where: { $0.id == script.id }) {
                        storage.scripts[idx].rename(renameTitle)
                        storage.save(storage.scripts[idx])
                    }
                    renameScript = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(renameTitle.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
    }

    // MARK: - Helpers

    private func loadScript(_ script: TeleprompterScript) {
        let doc = ScriptParser.parse(text: script.content)
        state.loadScript(script, document: doc)
        selectedScriptID = script.id
    }

    private func loadTestScript() {
        let test = TeleprompterScript.testScript
        // Save if not already saved
        if !storage.scripts.contains(where: { $0.title == test.title }) {
            storage.scripts.insert(test, at: 0)
            storage.save(test)
        }
        selectedScriptID = test.id
        loadScript(test)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let text = try ScriptParser.importFile(url: url)
                let title = url.deletingPathExtension().lastPathComponent
                let script = TeleprompterScript(title: title, content: text)
                storage.scripts.insert(script, at: 0)
                storage.save(script)
                selectedScriptID = script.id
            } catch {
                importError = error.localizedDescription
                showImportError = true
            }
        case .failure(let error):
            importError = error.localizedDescription
            showImportError = true
        }
    }

    private func durationText(_ script: TeleprompterScript) -> String {
        let seconds = script.estimatedDuration(wpm: settings.targetWPM)
        if seconds < 60 { return "<1 min" }
        let minutes = Int(seconds / 60)
        return "\(minutes) min"
    }
}
