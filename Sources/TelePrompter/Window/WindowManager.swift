import AppKit
import SwiftUI
import Combine

// MARK: - WindowManager
// Central coordinator for all window operations.

@MainActor
final class WindowManager: ObservableObject {

    @Published var isTeleprompterVisible: Bool = false
    @Published var availableScreens: [NSScreen] = NSScreen.screens
    @Published var selectedScreenIndex: Int = 0

    let teleprompterController: TeleprompterWindowController

    private var screenObserver: NSObjectProtocol?

    init(settings: AppSettings, state: TeleprompterState) {
        teleprompterController = TeleprompterWindowController(settings: settings, state: state)

        // Monitor screen configuration changes
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.availableScreens = NSScreen.screens
                self?.teleprompterController.ensureOnScreen()
            }
        }
    }

    func showTeleprompter() {
        teleprompterController.show()
        isTeleprompterVisible = true
    }

    func hideTeleprompter() {
        teleprompterController.hide()
        isTeleprompterVisible = false
    }

    func toggleTeleprompter() {
        if isTeleprompterVisible {
            hideTeleprompter()
        } else {
            showTeleprompter()
        }
    }

    func moveTeleprompterToScreen(at index: Int) {
        let screens = NSScreen.screens
        guard index < screens.count else { return }
        teleprompterController.move(to: screens[index])
        selectedScreenIndex = index
    }

    var screenNames: [String] {
        NSScreen.screens.enumerated().map { idx, screen in
            if screen == NSScreen.main {
                return "Display \(idx + 1) (Main)"
            }
            return "Display \(idx + 1)"
        }
    }
}
