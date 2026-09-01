import Foundation
import SwiftUI
import Combine

// MARK: - AppSettings (persisted via UserDefaults)

@MainActor
final class AppSettings: ObservableObject {

    // MARK: Teleprompter Appearance
    @Published var fontName: String {
        didSet { UserDefaults.standard.set(fontName, forKey: "fontName") }
    }
    @Published var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }
    @Published var fontWeight: Int {
        didSet { UserDefaults.standard.set(fontWeight, forKey: "fontWeight") }
    }
    @Published var lineSpacing: Double {
        didSet { UserDefaults.standard.set(lineSpacing, forKey: "lineSpacing") }
    }
    @Published var textAlignment: Int {
        didSet { UserDefaults.standard.set(textAlignment, forKey: "textAlignment") }
    }
    @Published var backgroundOpacity: Double {
        didSet { UserDefaults.standard.set(backgroundOpacity, forKey: "backgroundOpacity") }
    }
    @Published var textOpacity: Double {
        didSet { UserDefaults.standard.set(textOpacity, forKey: "textOpacity") }
    }
    @Published var mirrorMode: Bool {
        didSet { UserDefaults.standard.set(mirrorMode, forKey: "mirrorMode") }
    }
    @Published var alwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop") }
    }
    @Published var clickThrough: Bool {
        didSet { UserDefaults.standard.set(clickThrough, forKey: "clickThrough") }
    }
    @Published var windowX: Double {
        didSet { UserDefaults.standard.set(windowX, forKey: "windowX") }
    }
    @Published var windowY: Double {
        didSet { UserDefaults.standard.set(windowY, forKey: "windowY") }
    }
    @Published var windowWidth: Double {
        didSet { UserDefaults.standard.set(windowWidth, forKey: "windowWidth") }
    }
    @Published var windowHeight: Double {
        didSet { UserDefaults.standard.set(windowHeight, forKey: "windowHeight") }
    }

    // MARK: Highlight / Display
    @Published var highlightMode: HighlightMode {
        didSet { UserDefaults.standard.set(highlightMode.rawValue, forKey: "highlightMode") }
    }
    @Published var readingMode: ReadingMode {
        didSet { UserDefaults.standard.set(readingMode.rawValue, forKey: "readingMode") }
    }
    @Published var showProgress: Bool {
        didSet { UserDefaults.standard.set(showProgress, forKey: "showProgress") }
    }
    @Published var showWPM: Bool {
        didSet { UserDefaults.standard.set(showWPM, forKey: "showWPM") }
    }

    // MARK: Speech
    @Published var targetWPM: Double {
        didSet { UserDefaults.standard.set(targetWPM, forKey: "targetWPM") }
    }
    @Published var autoScrollWPM: Double {
        didSet { UserDefaults.standard.set(autoScrollWPM, forKey: "autoScrollWPM") }
    }
    @Published var matchingSensitivity: Double {
        didSet { UserDefaults.standard.set(matchingSensitivity, forKey: "matchingSensitivity") }
    }
    @Published var preferOnDeviceRecognition: Bool {
        didSet { UserDefaults.standard.set(preferOnDeviceRecognition, forKey: "preferOnDeviceRecognition") }
    }
    @Published var speechLocale: String {
        didSet { UserDefaults.standard.set(speechLocale, forKey: "speechLocale") }
    }

    // MARK: General
    @Published var autosaveEnabled: Bool {
        didSet { UserDefaults.standard.set(autosaveEnabled, forKey: "autosaveEnabled") }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }
    @Published var defaultScrollMode: ScrollMode {
        didSet { UserDefaults.standard.set(defaultScrollMode.rawValue, forKey: "defaultScrollMode") }
    }

    // MARK: Init (loads from UserDefaults)

    init() {
        let ud = UserDefaults.standard

        fontName            = ud.string(forKey: "fontName") ?? "SF Pro Display"
        fontSize            = ud.object(forKey: "fontSize") as? Double ?? 36
        fontWeight          = ud.object(forKey: "fontWeight") as? Int ?? 4 // .regular index
        lineSpacing         = ud.object(forKey: "lineSpacing") as? Double ?? 1.4
        textAlignment       = ud.object(forKey: "textAlignment") as? Int ?? 0 // leading
        backgroundOpacity   = ud.object(forKey: "backgroundOpacity") as? Double ?? 0.85
        textOpacity         = ud.object(forKey: "textOpacity") as? Double ?? 1.0
        mirrorMode          = ud.bool(forKey: "mirrorMode")
        alwaysOnTop         = ud.object(forKey: "alwaysOnTop") as? Bool ?? true
        clickThrough        = ud.bool(forKey: "clickThrough")
        windowX             = ud.object(forKey: "windowX") as? Double ?? 100
        windowY             = ud.object(forKey: "windowY") as? Double ?? 100
        windowWidth         = ud.object(forKey: "windowWidth") as? Double ?? 700
        windowHeight        = ud.object(forKey: "windowHeight") as? Double ?? 300

        highlightMode       = HighlightMode(rawValue: ud.string(forKey: "highlightMode") ?? "") ?? .sentence
        readingMode         = ReadingMode(rawValue: ud.string(forKey: "readingMode") ?? "") ?? .standard
        showProgress        = ud.object(forKey: "showProgress") as? Bool ?? true
        showWPM             = ud.object(forKey: "showWPM") as? Bool ?? true

        targetWPM           = ud.object(forKey: "targetWPM") as? Double ?? 150
        autoScrollWPM       = ud.object(forKey: "autoScrollWPM") as? Double ?? 150
        matchingSensitivity = ud.object(forKey: "matchingSensitivity") as? Double ?? 0.5
        preferOnDeviceRecognition = ud.object(forKey: "preferOnDeviceRecognition") as? Bool ?? true
        speechLocale        = ud.string(forKey: "speechLocale") ?? Locale.current.identifier

        autosaveEnabled     = ud.object(forKey: "autosaveEnabled") as? Bool ?? true
        hasCompletedOnboarding = ud.bool(forKey: "hasCompletedOnboarding")
        defaultScrollMode   = ScrollMode(rawValue: ud.string(forKey: "defaultScrollMode") ?? "") ?? .voiceFollow
    }

    // MARK: Computed helpers

    var resolvedFont: Font {
        .custom(fontName, size: fontSize)
            .weight(fontWeightValue)
    }

    var fontWeightValue: Font.Weight {
        switch fontWeight {
        case 0: return .ultraLight
        case 1: return .thin
        case 2: return .light
        case 3: return .regular
        case 4: return .medium
        case 5: return .semibold
        case 6: return .bold
        case 7: return .heavy
        case 8: return .black
        default: return .medium
        }
    }

    var resolvedTextAlignment: TextAlignment {
        switch textAlignment {
        case 0: return .leading
        case 1: return .center
        case 2: return .trailing
        default: return .leading
        }
    }

    func applyPreset(_ preset: AppearancePreset) {
        switch preset {
        case .small:
            fontSize = 24; lineSpacing = 1.2
        case .medium:
            fontSize = 36; lineSpacing = 1.4
        case .large:
            fontSize = 52; lineSpacing = 1.6
        case .presentation:
            fontSize = 72; lineSpacing = 1.8; backgroundOpacity = 0.95
        }
    }
}

enum AppearancePreset: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    case presentation = "Presentation"
}
