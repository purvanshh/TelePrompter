import SwiftUI
import AppKit

// MARK: - ScriptEditorView

struct ScriptEditorView: View {
    let scriptID: UUID
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var storage: ScriptStorage
    @EnvironmentObject var state: TeleprompterState
    @EnvironmentObject var sessionController: SessionController

    @State private var draftTitle: String = ""
    @State private var draftContent: String = ""
    @State private var searchText: String = ""
    @State private var replaceText: String = ""
    @State private var showFindReplace: Bool = false
    @State private var autosaveTask: Task<Void, Never>? = nil
    @State private var isEditing: Bool = false
    @FocusState private var titleFocused: Bool
    @FocusState private var editorFocused: Bool

    /// True only when this script is loaded in the teleprompter *and* the editor
    /// matches that loaded snapshot. Any edit flips the button back to Load.
    private var isLoadedAndUpToDate: Bool {
        guard let loaded = state.loadedScript, loaded.id == scriptID else { return false }
        return loaded.content == draftContent && loaded.title == draftTitle
    }

    private var wordCount: Int {
        draftContent.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }.count
    }

    private var characterCount: Int {
        draftContent.count
    }

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()
            if showFindReplace {
                findReplaceBar
                Divider()
            }
            textEditor
            Divider()
            statusBar
        }
        .onAppear {
            pullFromStorage()
        }
        .onChange(of: scriptID) { _, _ in
            autosaveTask?.cancel()
            pullFromStorage()
        }
        .onChange(of: draftContent) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: draftTitle) { _, _ in
            scheduleAutosave()
        }
        .onDisappear {
            autosaveTask?.cancel()
            commitToStorage()
            autosaveTask = nil
        }
    }

    // MARK: - Toolbar

    private var editorToolbar: some View {
        HStack(spacing: 8) {
            TextField("Script title", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.headline)
                .focused($titleFocused)
                .onSubmit {
                    titleFocused = false
                    commitToStorage()
                }

            Spacer()

            Button(action: loadIntoTeleprompter) {
                Label(
                    isLoadedAndUpToDate ? "Loaded" : "Load",
                    systemImage: isLoadedAndUpToDate ? "checkmark.tv" : "tv.badge.wifi"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(isLoadedAndUpToDate ? .green : .accentColor)
            .help(isLoadedAndUpToDate
                  ? "This version is loaded in the teleprompter"
                  : "Load this script in the teleprompter")
            .disabled(draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadedAndUpToDate)
            .focusable(false)

            Button {
                withAnimation { showFindReplace.toggle() }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Find and Replace (⌘F)")
            .keyboardShortcut("f", modifiers: .command)
            .focusable(false)

            Button {
                draftContent = ""
                commitToStorage()
            } label: {
                Image(systemName: "trash")
            }
            .help("Clear script content")
            .focusable(false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Text editor

    private var textEditor: some View {
        TextEditor(text: $draftContent)
            .font(.system(size: 14))
            .lineSpacing(3)
            .padding(8)
            .focused($editorFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                Group {
                    if draftContent.isEmpty {
                        VStack {
                            HStack {
                                Text("Paste or type your script here…")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 14))
                                    .padding(.top, 14)
                                    .padding(.leading, 14)
                                Spacer()
                            }
                            Spacer()
                        }
                        .allowsHitTesting(false)
                    }
                }
            )
    }

    // MARK: - Find/replace bar

    private var findReplaceBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            TextField("Replace", text: $replaceText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

            Button("Replace All") {
                if !searchText.isEmpty {
                    draftContent = draftContent.replacingOccurrences(
                        of: searchText,
                        with: replaceText
                    )
                    commitToStorage()
                }
            }
            .disabled(searchText.isEmpty)

            Spacer()

            Button {
                withAnimation { showFindReplace = false }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text("\(wordCount) words")
            Text("\(characterCount) characters")

            Spacer()

            HStack(spacing: 8) {
                Text("Est. duration:")
                    .foregroundStyle(.secondary)
                Menu {
                    ForEach([120.0, 150.0, 180.0], id: \.self) { wpm in
                        Button("\(Int(wpm)) WPM: \(durationText(wpm))") {
                            settings.targetWPM = wpm
                        }
                    }
                } label: {
                    Text("\(durationText(settings.targetWPM)) @ \(Int(settings.targetWPM)) WPM")
                        .foregroundStyle(.blue)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if isEditing {
                Text("Editing…")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func pullFromStorage() {
        guard let script = storage.scripts.first(where: { $0.id == scriptID }) else { return }
        draftTitle = script.title
        draftContent = script.content
        isEditing = false
    }

    /// Write drafts back to storage once — avoids republishing the script list on every keystroke.
    @discardableResult
    private func commitToStorage() -> TeleprompterScript? {
        guard let idx = storage.scripts.firstIndex(where: { $0.id == scriptID }) else { return nil }
        storage.scripts[idx].title = draftTitle.isEmpty ? "Untitled Script" : draftTitle
        storage.scripts[idx].content = draftContent
        storage.scripts[idx].modifiedAt = Date()
        let saved = storage.scripts[idx]
        storage.save(saved)
        storage.saveDraft(saved.content, scriptID: saved.id)
        isEditing = false
        return saved
    }

    private func loadIntoTeleprompter() {
        titleFocused = false
        editorFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)

        guard let saved = commitToStorage() else { return }
        let doc = ScriptParser.parse(text: saved.content)
        state.loadScript(saved, document: doc)
    }

    private func scheduleAutosave() {
        isEditing = true
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            commitToStorage()
        }
    }

    private func durationText(_ wpm: Double) -> String {
        let words = Double(max(wordCount, 1))
        let seconds = words / wpm * 60.0
        if seconds < 60 { return "<1 min" }
        let minutes = Int(seconds / 60)
        let secs = Int(seconds) % 60
        return secs > 0 ? "\(minutes)m \(secs)s" : "\(minutes)m"
    }
}
