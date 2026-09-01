import AppKit
import SwiftUI
import Combine

// MARK: - TeleprompterWindowController
// Manages the floating teleprompter overlay window with AppKit-level control.

@MainActor
final class TeleprompterWindowController: NSObject, NSWindowDelegate {

    private(set) var window: NSPanel?
    private var hostingView: NSView?

    // Settings & state passed in
    private var settings: AppSettings
    private var teleprompterState: TeleprompterState

    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings, state: TeleprompterState) {
        self.settings = settings
        self.teleprompterState = state
        super.init()
    }

    // MARK: - Create window

    func createWindow() {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }

        // Restore saved position/size
        let rect = NSRect(
            x: settings.windowX,
            y: settings.windowY,
            width: settings.windowWidth,
            height: settings.windowHeight
        )

        // Use NSPanel so it can float above fullscreen apps
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [
                .borderless,
                .resizable,
                .nonactivatingPanel,
                .hudWindow
            ],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.title = "TelePrompter"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow

        // Apply screen capture protection
        ScreenCaptureProtection.applyProtection(to: panel)

        // Apply always-on-top
        applyWindowLevel(to: panel)

        // Apply click-through
        applyClickThrough(to: panel)

        // Embed SwiftUI view
        let teleprompterView = TeleprompterOverlayView()
            .environmentObject(settings)
            .environmentObject(teleprompterState)

        let hosting = NSHostingView(rootView: teleprompterView)
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.hostingView = hosting

        self.window = panel

        // Validate screen position before showing
        ensureOnScreen()

        panel.orderFront(nil)
    }

    // MARK: - Show / hide

    func show() {
        if window == nil { createWindow() }
        window?.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    // MARK: - Window level (always on top)

    func applyWindowLevel(to panel: NSPanel? = nil) {
        let target = panel ?? window
        if settings.alwaysOnTop {
            target?.level = .floating
        } else {
            target?.level = .normal
        }
    }

    func updateAlwaysOnTop(_ value: Bool) {
        settings.alwaysOnTop = value
        applyWindowLevel()
    }

    // MARK: - Click-through

    func applyClickThrough(to panel: NSPanel? = nil) {
        let target = panel ?? window
        target?.ignoresMouseEvents = settings.clickThrough
    }

    func updateClickThrough(_ value: Bool) {
        settings.clickThrough = value
        applyClickThrough()
    }

    // MARK: - Screen capture protection toggle

    func updateCaptureProtection(_ enabled: Bool) {
        guard let window = window else { return }
        if enabled {
            ScreenCaptureProtection.applyProtection(to: window)
        } else {
            ScreenCaptureProtection.removeProtection(from: window)
        }
    }

    // MARK: - Multi-monitor: move to specific screen

    func move(to screen: NSScreen) {
        guard let window = window else { return }

        // Center on the target screen
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        let newOrigin = NSPoint(
            x: screenFrame.midX - windowFrame.width / 2,
            y: screenFrame.midY - windowFrame.height / 2
        )
        window.setFrameOrigin(newOrigin)
        savePosition()
    }

    // MARK: - Save/restore position

    func savePosition() {
        guard let window = window else { return }
        settings.windowX = window.frame.origin.x
        settings.windowY = window.frame.origin.y
        settings.windowWidth = window.frame.width
        settings.windowHeight = window.frame.height
    }

    // MARK: - Ensure on screen

    func ensureOnScreen() {
        guard let window = window else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        // Check if window origin is on any screen
        let windowOrigin = window.frame.origin
        let isOnScreen = screens.contains { screen in
            screen.frame.contains(windowOrigin)
        }

        if !isOnScreen {
            // Move to main screen center
            if let main = NSScreen.main {
                move(to: main)
            }
        }
    }

    // MARK: - Recording mode

    func enterRecordingMode() {
        guard let window = window else { return }
        // Ensure capture protection is active
        ScreenCaptureProtection.applyProtection(to: window)
        // Ensure always on top
        window.level = .floating
        // Disable click-through if interactive
        if !settings.clickThrough {
            window.ignoresMouseEvents = false
        }
    }

    func exitRecordingMode() {
        applyWindowLevel()
        applyClickThrough()
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowDidResize(_ notification: Notification) {
        Task { @MainActor in
            savePosition()
        }
    }

    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor in
            savePosition()
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            savePosition()
        }
    }

    // MARK: - Diagnostics

    var protectionReport: String {
        guard let window = window else {
            return "Teleprompter window is not open."
        }
        return ScreenCaptureProtection.diagnosticReport(for: window)
    }
}
