import SwiftUI
import AppKit

// MARK: - TelePrompterApp

@main
struct TelePrompterApp: App {

    @StateObject private var settings       = AppSettings()
    @StateObject private var teleState      = TeleprompterState()
    @StateObject private var storage        = ScriptStorage()

    // WindowManager and SessionController depend on the above, built lazily
    @StateObject private var windowManager: WindowManager
    @StateObject private var sessionController: SessionController

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        let s = AppSettings()
        let ts = TeleprompterState()
        let st = ScriptStorage()
        let wm = WindowManager(settings: s, state: ts)
        let sc = SessionController(settings: s, state: ts, storage: st, windowManager: wm)

        _settings          = StateObject(wrappedValue: s)
        _teleState         = StateObject(wrappedValue: ts)
        _storage           = StateObject(wrappedValue: st)
        _windowManager     = StateObject(wrappedValue: wm)
        _sessionController = StateObject(wrappedValue: sc)
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(settings)
                .environmentObject(teleState)
                .environmentObject(storage)
                .environmentObject(windowManager)
                .environmentObject(sessionController)
                .onAppear {
                    // Pass delegate references
                    appDelegate.sessionController = sessionController
                    appDelegate.windowManager = windowManager
                    appDelegate.settings = settings
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            AppMenuCommands(
                sessionController: sessionController,
                windowManager: windowManager,
                settings: settings,
                state: teleState
            )
        }

        // Settings window (macOS 13+)
        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(sessionController)
                .frame(width: 560, height: 480)
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var sessionController: SessionController?
    weak var windowManager: WindowManager?
    weak var settings: AppSettings?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep running when teleprompter is open
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            sessionController?.stopFollowing()
            windowManager?.teleprompterController.savePosition()
        }
    }
}

// MARK: - Menu Commands

struct AppMenuCommands: Commands {
    let sessionController: SessionController
    let windowManager: WindowManager
    let settings: AppSettings
    let state: TeleprompterState

    var body: some Commands {
        // File menu
        CommandGroup(replacing: .newItem) {
            Button("New Script") {
                // Handled in ScriptLibraryView
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Import Script…") {
                // Handled in ScriptLibraryView
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        // Teleprompter menu
        CommandMenu("Teleprompter") {
            Button(state.followingState.isActive ? "Stop Following" : "Start Following") {
                Task { @MainActor in sessionController.toggleFollowing() }
            }
            .keyboardShortcut(.return, modifiers: .command)

            Button("Pause Following") {
                Task { @MainActor in sessionController.pauseFollowing() }
            }
            .keyboardShortcut(" ", modifiers: [])

            Button("Reset Position") {
                Task { @MainActor in sessionController.seekToBeginning() }
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Divider()

            Button(windowManager.isTeleprompterVisible ? "Hide Teleprompter" : "Show Teleprompter") {
                Task { @MainActor in windowManager.toggleTeleprompter() }
            }

            Button(settings.readingMode == .recording ? "Exit Recording Mode" : "Enter Recording Mode") {
                Task { @MainActor in sessionController.toggleRecordingMode() }
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Toggle("Always on Top", isOn: Binding(
                get: { settings.alwaysOnTop },
                set: { v in
                    Task { @MainActor in
                        settings.alwaysOnTop = v
                        windowManager.teleprompterController.updateAlwaysOnTop(v)
                    }
                }
            ))

            Toggle("Click Through", isOn: Binding(
                get: { settings.clickThrough },
                set: { v in
                    Task { @MainActor in
                        settings.clickThrough = v
                        windowManager.teleprompterController.updateClickThrough(v)
                    }
                }
            ))

            Toggle("Mirror Mode", isOn: Binding(
                get: { settings.mirrorMode },
                set: { v in settings.mirrorMode = v }
            ))
        }

        // Help menu additions
        CommandGroup(after: .help) {
            Button("Screen Recording Protection") {
                // Opens privacy settings tab
            }
            Button("Troubleshooting Guide") {
                if let url = URL(string: "https://github.com/teleprompter-app/help") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
