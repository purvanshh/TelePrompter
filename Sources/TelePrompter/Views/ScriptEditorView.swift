import SwiftUI

// MARK: - ScriptEditorView

struct ScriptEditorView: View {
    @Binding var script: TeleprompterScript
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var storage: ScriptStorage
    @EnvironmentObject var state: TeleprompterState
    @EnvironmentObject var sessionController: SessionController

    @State private var searchText: String = ""
    @State private var replaceText: String = ""
    @State private var showFindReplace: Bool = false
    @State private var autosaveTimer: Timer? = nil
    @State private var isEditing: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Editor toolbar
            editorToolbar

            Divider()

            // Find/replace bar
            if showFindReplace {
                findReplaceBar
                Divider()
            }

            // Text editor
            textEditor

            Divider()

            // Status bar
            statusBar
        }
        .onChange(of: script.content) { _, _ in
            scheduleAutosave()
        }
    }

    // MARK: - Toolbar

    private var editorToolbar: some View {
        HStack(spacing: 8) {
            // Title
            TextField("Script title", text: $script.title)
                .textFieldStyle(.plain)
                .font(.headline)
                .onSubmit {
                    storage.save(script)
                }

            Spacer()

            // Load in teleprompter
            Button {
                let doc = ScriptParser.parse(text: script.content)
                state.loadScript(script, document: doc)
            } label: {
                Label("Load", systemImage: "tv.badge.wifi")
            }
            .buttonStyle(.borderedProminent)
            .help("Load this script in the teleprompter")
            .disabled(script.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            // Find/replace toggle
            Button {
                withAnimation { showFindReplace.toggle() }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Find and Replace (⌘F)")
            .keyboardShortcut("f", modifiers: .command)

            // Clear
            Button {
                script.content = ""
                storage.save(script)
            } label: {
                Image(systemName: "trash")
            }
            .help("Clear script content")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Text editor

    private var textEditor: some View {
        TextEditor(text: $script.content)
            .font(.system(size: 14))
            .lineSpacing(3)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                Group {
                    if script.content.isEmpty {
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
                    script.content = script.content.replacingOccurrences(
                        of: searchText,
                        with: replaceText
                    )
                    storage.save(script)
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
            Text("\(script.wordCount) words")
            Text("\(script.characterCount) characters")

            Spacer()

            // Duration estimates
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

            // Autosave indicator
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

    // MARK: - Autosave

    private func scheduleAutosave() {
        isEditing = true
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            Task { @MainActor in
                storage.save(script)
                // Also save draft for crash recovery
                storage.saveDraft(script.content, scriptID: script.id)
                isEditing = false
            }
        }
    }

    private func durationText(_ wpm: Double) -> String {
        let seconds = script.estimatedDuration(wpm: wpm)
        if seconds < 60 { return "<1 min" }
        let minutes = Int(seconds / 60)
        let secs = Int(seconds) % 60
        return secs > 0 ? "\(minutes)m \(secs)s" : "\(minutes)m"
    }
}
