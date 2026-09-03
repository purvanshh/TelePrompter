import SwiftUI
import Speech

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var sessionController: SessionController

    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general    = "General"
        case appearance = "Appearance"
        case speech     = "Speech"
        case shortcuts  = "Shortcuts"
        case privacy    = "Privacy"

        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .general:    return "gear"
            case .appearance: return "paintbrush"
            case .speech:     return "waveform"
            case .shortcuts:  return "keyboard"
            case .privacy:    return "lock.shield"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)

            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(SettingsTab.appearance)

            SpeechSettingsTab()
                .tabItem { Label("Speech", systemImage: "waveform") }
                .tag(SettingsTab.speech)

            ShortcutsSettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)

            PrivacySettingsTab()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
                .tag(SettingsTab.privacy)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Autosave scripts", isOn: $settings.autosaveEnabled)
                Picker("Default scroll mode", selection: $settings.defaultScrollMode) {
                    ForEach(ScrollMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
            }
            Section("Reading Speed") {
                HStack {
                    Text("Target WPM")
                    Spacer()
                    Stepper("\(Int(settings.targetWPM)) WPM",
                            value: $settings.targetWPM,
                            in: 60...400, step: 10)
                }
                HStack {
                    Text("Auto-scroll WPM")
                    Spacer()
                    Stepper("\(Int(settings.autoScrollWPM)) WPM",
                            value: $settings.autoScrollWPM,
                            in: 60...400, step: 10)
                }
            }
            Section("Display") {
                Toggle("Show progress indicator", isOn: $settings.showProgress)
                Toggle("Show WPM indicator", isOn: $settings.showWPM)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

struct AppearanceSettingsTab: View {
    @EnvironmentObject var settings: AppSettings

    private let availableFonts = ["SF Pro Display", "Helvetica Neue", "Georgia",
                                   "Times New Roman", "Courier New", "Menlo",
                                   "Futura", "Gill Sans"]

    var body: some View {
        Form {
            Section("Font") {
                Picker("Font Family", selection: $settings.fontName) {
                    ForEach(availableFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                HStack {
                    Text("Font Size")
                    Slider(value: $settings.fontSize, in: 16...96)
                    Text("\(Int(settings.fontSize)) pt")
                        .frame(width: 50, alignment: .trailing)
                }
                Picker("Font Weight", selection: $settings.fontWeight) {
                    Text("Light").tag(2)
                    Text("Regular").tag(3)
                    Text("Medium").tag(4)
                    Text("Semibold").tag(5)
                    Text("Bold").tag(6)
                    Text("Heavy").tag(7)
                }
                .pickerStyle(.menu)
            }
            Section("Layout") {
                HStack {
                    Text("Line Spacing")
                    Slider(value: $settings.lineSpacing, in: 1.0...2.5)
                    Text(String(format: "%.1f×", settings.lineSpacing))
                        .frame(width: 40, alignment: .trailing)
                }
                Picker("Text Alignment", selection: $settings.textAlignment) {
                    Image(systemName: "text.alignleft").tag(0)
                    Image(systemName: "text.aligncenter").tag(1)
                    Image(systemName: "text.alignright").tag(2)
                }
                .pickerStyle(.segmented)
            }
            Section("Colors & Opacity") {
                HStack {
                    Text("Background Opacity")
                    Slider(value: $settings.backgroundOpacity, in: 0...1)
                    Text(String(format: "%.0f%%", settings.backgroundOpacity * 100))
                        .frame(width: 40, alignment: .trailing)
                }
                HStack {
                    Text("Text Opacity")
                    Slider(value: $settings.textOpacity, in: 0.3...1)
                    Text(String(format: "%.0f%%", settings.textOpacity * 100))
                        .frame(width: 40, alignment: .trailing)
                }
            }
            Section("Highlighting") {
                Picker("Highlight Mode", selection: $settings.highlightMode) {
                    ForEach(HighlightMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Presets") {
                HStack(spacing: 8) {
                    ForEach(AppearancePreset.allCases, id: \.self) { preset in
                        Button(preset.rawValue) {
                            settings.applyPreset(preset)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Speech

struct SpeechSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var sessionController: SessionController

    var availableLocales: [(Locale, String)] {
        SFSpeechRecognizer.supportedLocales()
            .compactMap { locale -> (Locale, String)? in
                let name = Locale.current.localizedString(forIdentifier: locale.identifier)
                    ?? locale.identifier
                return (locale, name)
            }
            .sorted { $0.1 < $1.1 }
    }

    var body: some View {
        Form {
            Section("Microphone") {
                MicrophoneSectionView()
            }
            Section("Recognition") {
                Toggle("Prefer on-device recognition", isOn: $settings.preferOnDeviceRecognition)
                    .help("When enabled, audio is processed locally without internet. Availability depends on your Mac and language.")

                HStack {
                    Text("Match Leniency")
                    Slider(value: $settings.matchingSensitivity, in: 0...1)
                    Text(sensitivityLabel)
                        .frame(width: 70, alignment: .trailing)
                }
                .help("Strict: higher confidence, smaller search window, fewer jumps. Lenient: moves more easily on weaker matches.")

                Picker("Language", selection: $settings.speechLocale) {
                    ForEach(availableLocales, id: \.0.identifier) { locale, name in
                        Text(name).tag(locale.identifier)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var sensitivityLabel: String {
        switch settings.matchingSensitivity {
        case 0..<0.33:  return "Strict"
        case 0.33..<0.66: return "Normal"
        default:        return "Lenient"
        }
    }
}

// MARK: - Microphone section (reusable)

struct MicrophoneSectionView: View {
    @EnvironmentObject var sessionController: SessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let audioService = sessionController.audioInputService

            if !audioService.micPermissionGranted {
                HStack {
                    Image(systemName: "mic.slash.fill")
                        .foregroundStyle(.red)
                    Text("Microphone access is required for voice following.")
                        .font(.subheadline)
                }
                Button("Open Privacy Settings") {
                    audioService.openPrivacySettings()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Picker("Input Device", selection: Binding(
                    get: { audioService.selectedDeviceID ?? "" },
                    set: { audioService.selectedDeviceID = $0 }
                )) {
                    ForEach(audioService.availableDevices) { device in
                        HStack {
                            Text(device.name)
                            if device.isDefault { Text("(Default)").foregroundStyle(.secondary) }
                        }
                        .tag(device.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsSettingsTab: View {
    var body: some View {
        Form {
            Section("Voice Following") {
                ShortcutRow("Start / Stop Following", shortcut: "⌘↩")
                ShortcutRow("Pause / Resume", shortcut: "Space")
            }
            Section("Navigation") {
                ShortcutRow("Previous Sentence", shortcut: "↑")
                ShortcutRow("Next Sentence", shortcut: "↓")
                ShortcutRow("Go to Beginning", shortcut: "⌘↑")
                ShortcutRow("Go to End", shortcut: "⌘↓")
            }
            Section("Modes") {
                ShortcutRow("Toggle Recording Mode", shortcut: "⌘R")
                ShortcutRow("Exit Recording Mode", shortcut: "Escape")
            }
            Section {
                Text("Global hotkeys require Accessibility permission. Customize shortcuts in a future update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutRow: View {
    let action: String
    let shortcut: String

    init(_ action: String, shortcut: String) {
        self.action = action
        self.shortcut = shortcut
    }

    var body: some View {
        HStack {
            Text(action)
            Spacer()
            Text(shortcut)
                .font(.system(.subheadline, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - Privacy

struct PrivacySettingsTab: View {
    @EnvironmentObject var sessionController: SessionController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Data handling
                privacySection(
                    icon: "lock.fill",
                    title: "Your Data Stays on Your Mac",
                    body: """
                    TelePrompter processes everything locally. Your scripts, \
                    your audio, and all transcription stay on your device. \
                    No account is required, no server is involved, and nothing \
                    is uploaded.
                    """
                )

                privacySection(
                    icon: "mic.fill",
                    title: "Microphone Usage",
                    body: """
                    Microphone audio is passed directly to Apple's on-device \
                    Speech Recognition framework. When on-device recognition is \
                    enabled (recommended), audio never leaves your Mac. If \
                    on-device recognition is unavailable for your selected language, \
                    Apple's framework may use network processing — this is indicated \
                    in Speech Settings.
                    """
                )

                privacySection(
                    icon: "video.slash.fill",
                    title: "Screen Recording Protection",
                    body: ScreenCaptureProtection.protectionExplanation
                )

                privacySection(
                    icon: "antenna.radiowaves.left.and.right.slash",
                    title: "No Network Requests",
                    body: """
                    TelePrompter makes no network requests of its own. There are \
                    no analytics, no telemetry, no crash reporting, and no cloud \
                    synchronization built into this application.
                    """
                )

                // Test protection button
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Screen Recording Protection Test",
                              systemImage: "checkmark.shield")
                            .font(.headline)

                        Text("To verify that the teleprompter is excluded from your screen recording:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. Show the teleprompter overlay (click Show Overlay).")
                            Text("2. Start a QuickTime Player or macOS Screenshot recording.")
                            Text("3. Record for a few seconds.")
                            Text("4. Stop recording and review the file.")
                            Text("5. The teleprompter should not appear in the recording.")
                        }
                        .font(.callout)

                        Text("Note: OBS Studio Display Capture may still show the window. See the Teleprompter tab for details.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
    }

    private func privacySection(icon: String, title: String, body: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.headline)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
