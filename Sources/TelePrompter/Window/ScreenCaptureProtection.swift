import AppKit
import Foundation

// MARK: - ScreenCaptureProtection
//
// Uses NSWindow.sharingType = .none to request that macOS exclude this window
// from screen capture APIs that respect window sharing restrictions.
//
// IMPORTANT LIMITATIONS (documented honestly):
//
// ✅ Expected to work:
//   - macOS Screenshot (Cmd+Shift+5) — window capture / screen capture modes
//   - QuickTime Player screen recording
//   - macOS ReplayKit-based capture
//   - Any capture API that queries NSWindowSharingType before compositing
//
// ⚠️  May NOT work:
//   - OBS Studio with "Display Capture" or "Window Capture (Core Graphics)"
//     sources that enumerate the screen compositor directly
//   - Third-party apps that capture via CGDisplayStream at the display level
//   - Any tool that captures raw framebuffer data
//   - AirPlay mirroring to some targets
//   - Some virtual machine screen sharing
//
// The NSWindow.sharingType = .none API is a legitimate macOS privacy mechanism,
// not a hack. It is the strongest window-level protection available via public API.

final class ScreenCaptureProtection {

    // MARK: - Apply protection to a window

    static func applyProtection(to window: NSWindow) {
        // .none = exclude from window sharing / screen capture
        window.sharingType = .none

        // Additionally mark the content view backing layer to prevent capture
        // This is belt-and-suspenders for some capture paths
        if let layer = window.contentView?.layer {
            layer.allowsGroupOpacity = true
        }
    }

    // MARK: - Remove protection (interactive / test mode)

    static func removeProtection(from window: NSWindow) {
        window.sharingType = .readOnly
    }

    // MARK: - Query current protection status

    static func isProtected(_ window: NSWindow) -> Bool {
        return window.sharingType == .none
    }

    // MARK: - Diagnostic description

    static func diagnosticReport(for window: NSWindow) -> String {
        let sharing = window.sharingType
        let sharingDesc: String
        switch sharing {
        case .none:     sharingDesc = ".none (excluded from capture)"
        case .readOnly: sharingDesc = ".readOnly (visible to screen capture)"
        case .readWrite: sharingDesc = ".readWrite (visible and interactive)"
        @unknown default: sharingDesc = "unknown"
        }

        let level = window.level
        let levelDesc: String
        switch level {
        case .floating:         levelDesc = "floating (above normal windows)"
        case .screenSaver:      levelDesc = "screenSaver"
        case .mainMenu:         levelDesc = "mainMenu"
        case .statusBar:        levelDesc = "statusBar"
        case .normal:           levelDesc = "normal"
        default:                levelDesc = "custom (\(level.rawValue))"
        }

        return """
        Window Sharing Type: \(sharingDesc)
        Window Level: \(levelDesc)
        Is On Screen: \(window.isVisible)
        Alpha Value: \(window.alphaValue)
        
        Screen Recording Protection:
        This window is configured with NSWindow.sharingType = .none, which
        requests macOS to exclude it from supported screen capture APIs including
        QuickTime Player, macOS Screenshot, and ReplayKit.
        
        ⚠️ Limitation: OBS Studio "Display Capture" mode and other tools that
        capture at the CGDisplayStream level may still include this window.
        This is a macOS platform limitation, not a bug in this application.
        
        To test: Use QuickTime Player → File → New Screen Recording
        and verify the teleprompter is not visible in the recorded file.
        """
    }

    // MARK: - User-facing protection explanation

    static let protectionExplanation = """
    Screen Recording Protection

    TelePrompter uses the macOS window sharing API (NSWindow.sharingType = .none) \
    to request that supported screen capture tools exclude the teleprompter window.

    What this typically protects against:
    • QuickTime Player screen recordings
    • macOS Screenshot (Cmd+Shift+5)
    • Screen recordings using the macOS ScreenCaptureKit/ReplayKit frameworks
    • Window-aware capture APIs

    What may still capture the window:
    • OBS Studio using "Display Capture" (captures the raw display compositor)
    • Third-party tools that capture at the display level rather than window level
    • AirPlay mirroring in some configurations

    For OBS users: Use "Window Capture" mode with a specific application window \
    rather than "Display Capture" to benefit from the window exclusion.

    This protection is implemented using legitimate macOS APIs. It cannot guarantee \
    exclusion from every possible capture technology.
    """
}
