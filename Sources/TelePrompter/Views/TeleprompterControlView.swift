import SwiftUI

// MARK: - TeleprompterControlView
// The main control panel for the teleprompter session.

struct TeleprompterControlView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var state: TeleprompterState
    @EnvironmentObject var windowManager: WindowManager
    @EnvironmentObject var sessionController: SessionController
    @EnvironmentObject var storage: ScriptStorage

    @State private var showDiagnostics: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Script status
                scriptStatusCard

                // Primary controls
                primaryControlsCard

                // Position controls
                positionControlsCard

                // Display settings
                displaySettingsCard

                // Window settings
                windowSettingsCard

                // Multi-monitor
                if windowManager.availableScreens.count > 1 {
                    multiMonitorCard
                }

                // Diagnostics
                diagnosticsCard
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Script status card

    private var scriptStatusCard: some View {
        GroupBox {
            if let script = state.loadedScript {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.blue)
                            Text(script.title)
                                .font(.headline)
                        }
                        HStack(spacing: 12) {
                            Label("\(state.document.totalWords) words", systemImage: "textformat.123")
                            Label("\(state.document.totalSentences) sentences", systemImage: "text.alignleft")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(Int(state.progressFraction * 100))%")
                            .font(.title2.bold())
                            .foregroundStyle(.blue)
                        Text("complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue)
                            .frame(width: geo.size.width * state.progressFraction, height: 6)
                    }
                }
                .frame(height: 6)
            } else {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text("No script loaded")
                        .foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink("Load a Script") {
                        ScriptLibraryView()
                    }
                    .buttonStyle(.bordered)
                }
            }
        } label: {
            Label("Script", systemImage: "doc.text")
        }
    }

    // MARK: - Primary controls

    private var primaryControlsCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                // Following state indicator
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(state.followingState.displayText)
                        .font(.subheadline)

                    Spacer()

                    // Audio level
                    if state.followingState.isActive {
                        AudioLevelView(level: state.audioLevel)
                            .frame(width: 50, height: 14)
                    }
                }

                // Main buttons
                HStack(spacing: 12) {
                    // Show/hide teleprompter
                    Button {
                        windowManager.toggleTeleprompter()
                    } label: {
                        Label(
                            windowManager.isTeleprompterVisible ? "Hide Overlay" : "Show Overlay",
                            systemImage: windowManager.isTeleprompterVisible ? "eye.slash" : "eye"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    // Start/stop following
                    Button {
                        sessionController.toggleFollowing()
                    } label: {
                        Label(
                            state.followingState.isActive ? "Stop Following" : "Start Following",
                            systemImage: state.followingState.isActive ? "stop.circle.fill" : "waveform.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(state.followingState.isActive ? .red : .green)
                    .disabled(state.document.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }

                // Secondary buttons
                HStack(spacing: 8) {
                    Button {
                        sessionController.pauseFollowing()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!state.followingState.isActive)

                    Button {
                        state.jumpToBeginning()
                    } label: {
                        Label("Reset", systemImage: "backward.end.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.upArrow, modifiers: .command)

                    Button {
                        sessionController.toggleRecordingMode()
                    } label: {
                        Label(
                            settings.readingMode == .recording ? "Exit Recording" : "Recording Mode",
                            systemImage: "record.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(settings.readingMode == .recording ? .red : .primary)
                }
            }
        } label: {
            Label("Controls", systemImage: "play.circle")
        }
    }

    // MARK: - Position controls

    private var positionControlsCard: some View {
        GroupBox {
            VStack(spacing: 8) {
                // Current position info
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Word \(state.currentWordIndex + 1) of \(state.document.totalWords)")
                            .font(.subheadline)
                        Text("Sentence \(state.currentSentenceIndex + 1) of \(state.document.totalSentences)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Confidence: \(Int(state.alignmentConfidence * 100))%")
                            .font(.caption)
                            .foregroundStyle(confidenceColor)
                        Text(remainingTimeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Scroll mode picker
                HStack {
                    Text("Mode:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Scroll Mode", selection: $settings.defaultScrollMode) {
                        ForEach(ScrollMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: settings.defaultScrollMode) { _, newMode in
                        state.scrollMode = newMode
                    }
                }

                // Manual navigation arrows
                HStack(spacing: 16) {
                    Button {
                        let prev = max(0, state.currentSentenceIndex - 1)
                        state.jumpToSentence(prev)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .keyboardShortcut(.upArrow, modifiers: [])
                    .help("Previous sentence (↑)")

                    Button {
                        let next = min(state.document.totalSentences - 1, state.currentSentenceIndex + 1)
                        state.jumpToSentence(next)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .keyboardShortcut(.downArrow, modifiers: [])
                    .help("Next sentence (↓)")

                    Spacer()

                    // Jump to paragraph
                    if state.document.paragraphs.count > 1 {
                        Menu("Jump to Paragraph") {
                            ForEach(state.document.paragraphs) { para in
                                Button {
                                    state.jumpToSentence(para.sentenceRange.lowerBound)
                                } label: {
                                    let preview = String(para.text.prefix(50))
                                    Text("¶\(para.id + 1): \(preview)…")
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
        } label: {
            Label("Position", systemImage: "scope")
        }
    }

    // MARK: - Display settings

    private var displaySettingsCard: some View {
        GroupBox {
            VStack(spacing: 10) {
                // Font size
                LabeledSlider("Font Size", value: $settings.fontSize,
                              range: 16...96, format: "%.0f pt")

                // Background opacity
                LabeledSlider("Background", value: $settings.backgroundOpacity,
                              range: 0...1, format: "%.0f%%", multiplier: 100)

                // Line spacing
                LabeledSlider("Line Spacing", value: $settings.lineSpacing,
                              range: 1.0...2.5, format: "%.1f×")

                // Highlight mode
                HStack {
                    Text("Highlight")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Picker("Highlight Mode", selection: $settings.highlightMode) {
                        ForEach(HighlightMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Text alignment
                HStack {
                    Text("Alignment")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Picker("Alignment", selection: $settings.textAlignment) {
                        Image(systemName: "text.alignleft").tag(0)
                        Image(systemName: "text.aligncenter").tag(1)
                        Image(systemName: "text.alignright").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 120)
                    Spacer()
                }

                // Appearance presets
                HStack {
                    Text("Preset")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    HStack(spacing: 6) {
                        ForEach(AppearancePreset.allCases, id: \.self) { preset in
                            Button(preset.rawValue) {
                                settings.applyPreset(preset)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                    Spacer()
                }
            }
        } label: {
            Label("Display", systemImage: "textformat")
        }
    }

    // MARK: - Window settings

    private var windowSettingsCard: some View {
        GroupBox {
            VStack(spacing: 10) {
                Toggle("Always on Top", isOn: $settings.alwaysOnTop)
                    .onChange(of: settings.alwaysOnTop) { _, val in
                        windowManager.teleprompterController.updateAlwaysOnTop(val)
                    }

                Toggle("Click-Through Mode", isOn: $settings.clickThrough)
                    .onChange(of: settings.clickThrough) { _, val in
                        windowManager.teleprompterController.updateClickThrough(val)
                    }

                Toggle("Mirror Mode (Horizontal)", isOn: $settings.mirrorMode)

                Divider()

                Toggle("Show Progress", isOn: $settings.showProgress)
                Toggle("Show WPM", isOn: $settings.showWPM)
            }
        } label: {
            Label("Window", systemImage: "macwindow")
        }
    }

    // MARK: - Multi-monitor

    private var multiMonitorCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Move teleprompter to:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(windowManager.screenNames.indices, id: \.self) { idx in
                        Button(windowManager.screenNames[idx]) {
                            windowManager.moveTeleprompterToScreen(at: idx)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
            }
        } label: {
            Label("Displays (\(windowManager.availableScreens.count))", systemImage: "display.2")
        }
    }

    // MARK: - Diagnostics card

    private var diagnosticsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show Diagnostics", isOn: $showDiagnostics)

                if showDiagnostics {
                    Divider()
                    Text(windowManager.teleprompterController.protectionReport)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Speech State: \(state.followingState.displayText)")
                        Text("Current Word: \(state.currentWordIndex)")
                        Text("Current Sentence: \(state.currentSentenceIndex)")
                        Text("Confidence: \(String(format: "%.2f", state.alignmentConfidence))")
                        Text("Transcript: \(state.transcriptBuffer.prefix(80))...")
                        Text("Audio Level: \(String(format: "%.2f", state.audioLevel))")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Screen Recording & Diagnostics", systemImage: "stethoscope")
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch state.followingState {
        case .following:     return .green
        case .listening:     return .blue
        case .paused:        return .yellow
        case .lowConfidence: return .orange
        case .error:         return .red
        default:             return .gray
        }
    }

    private var confidenceColor: Color {
        if state.alignmentConfidence > 0.6 { return .green }
        if state.alignmentConfidence > 0.35 { return .yellow }
        return .red
    }

    private var remainingTimeText: String {
        let seconds = state.estimatedRemainingTime
        guard seconds > 0 else { return "" }
        let minutes = Int(seconds / 60)
        let secs = Int(seconds) % 60
        return "~\(minutes)m \(secs)s remaining"
    }
}

// MARK: - LabeledSlider helper

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var multiplier: Double = 1.0

    init(_ label: String, value: Binding<Double>, range: ClosedRange<Double>,
         format: String, multiplier: Double = 1.0) {
        self.label = label
        self._value = value
        self.range = range
        self.format = format
        self.multiplier = multiplier
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: format, value * multiplier))
                .font(.caption.monospacedDigit())
                .frame(width: 52, alignment: .trailing)
        }
    }
}
