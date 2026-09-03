import Foundation
import Combine

// MARK: - Following State

enum FollowingState: Equatable {
    case idle
    case ready
    case listening
    case following
    case paused
    case micUnavailable
    case speechUnavailable
    case lowConfidence
    case complete
    case error(String)

    var displayText: String {
        switch self {
        case .idle:              return "Ready"
        case .ready:             return "Ready"
        case .listening:         return "Listening…"
        case .following:         return "Following"
        case .paused:            return "Paused"
        case .micUnavailable:    return "Microphone Unavailable"
        case .speechUnavailable: return "Speech Unavailable"
        case .lowConfidence:     return "Low Confidence"
        case .complete:          return "Script Complete"
        case .error(let msg):    return "Error: \(msg)"
        }
    }

    var isActive: Bool {
        switch self {
        case .listening, .following, .lowConfidence: return true
        default: return false
        }
    }

    var symbolName: String {
        switch self {
        case .idle, .ready:      return "mic"
        case .listening:         return "mic.fill"
        case .following:         return "waveform"
        case .paused:            return "pause.circle"
        case .micUnavailable:    return "mic.slash"
        case .speechUnavailable: return "exclamationmark.bubble"
        case .lowConfidence:     return "questionmark.circle"
        case .complete:          return "checkmark.circle"
        case .error:             return "exclamationmark.triangle"
        }
    }
}

// MARK: - Scroll Mode

enum ScrollMode: String, CaseIterable, Codable {
    case voiceFollow = "Voice Follow"
    case autoScroll  = "Auto Scroll"
    case manual      = "Manual"
}

// MARK: - Highlight Mode

enum HighlightMode: String, CaseIterable, Codable {
    case none     = "None"
    case sentence = "Sentence"
    case word     = "Word"
    case progress = "Progress"
}

// MARK: - Reading Mode

enum ReadingMode: String, CaseIterable, Codable {
    case standard    = "Standard"
    case focus       = "Focus"
    case presentation = "Presentation"
    case recording   = "Recording"
}

// MARK: - TeleprompterState

@MainActor
final class TeleprompterState: ObservableObject {

    // Script
    @Published var document: ScriptDocument = .empty
    @Published var loadedScript: TeleprompterScript? = nil

    // Position
    @Published var currentWordIndex: Int = 0
    @Published var currentSentenceIndex: Int = 0
    @Published var currentParagraphIndex: Int = 0
    @Published var alignmentConfidence: Double = 0.0

    // Following
    @Published var followingState: FollowingState = .idle
    @Published var scrollMode: ScrollMode = .voiceFollow
    @Published var highlightMode: HighlightMode = .sentence
    @Published var readingMode: ReadingMode = .standard

    // Transcript buffer (last N words seen)
    @Published var transcriptBuffer: String = ""
    @Published var latestPartial: String = ""

    // Audio
    @Published var audioLevel: Float = 0.0
    @Published var selectedMicrophoneID: String? = nil

    // Session stats
    @Published var sessionStartTime: Date? = nil
    @Published var actualWPM: Double = 0.0
    @Published var wordsSpokenCount: Int = 0

    /// Fired when the user manually changes position (arrows, reset, overlay tap).
    /// SessionController uses this to re-anchor the alignment engine.
    private let manualSeekSubject = PassthroughSubject<Int, Never>()
    var manualSeekPublisher: AnyPublisher<Int, Never> {
        manualSeekSubject.eraseToAnyPublisher()
    }

    // Progress
    var progressFraction: Double {
        guard document.totalWords > 0 else { return 0 }
        return Double(currentWordIndex) / Double(document.totalWords)
    }

    var estimatedRemainingTime: TimeInterval {
        guard document.totalWords > 0, actualWPM > 0 else { return 0 }
        let remaining = document.totalWords - currentWordIndex
        return Double(remaining) / actualWPM * 60.0
    }

    // MARK: - Mutations

    func loadScript(_ script: TeleprompterScript, document: ScriptDocument) {
        self.loadedScript = script
        self.document = document
        resetPosition()
    }

    func resetPosition() {
        currentWordIndex = 0
        currentSentenceIndex = 0
        currentParagraphIndex = 0
        alignmentConfidence = 0.0
        transcriptBuffer = ""
        latestPartial = ""
        if followingState == .complete { followingState = .ready }
        manualSeekSubject.send(0)
    }

    func advanceToWord(_ index: Int, confidence: Double) {
        guard index >= 0 && index < document.totalWords else { return }
        currentWordIndex = index
        alignmentConfidence = confidence

        if let sentence = document.sentence(containingWord: index) {
            currentSentenceIndex = sentence.id
        }
        if let para = document.paragraph(containingWord: index) {
            currentParagraphIndex = para.id
        }

        // Check completion — only when at the last sentence
        if index >= document.totalWords - 1 {
            followingState = .complete
        } else if followingState != .paused && followingState != .complete {
            // High confidence → following, low → lowConfidence, but never demote from .following to .listening
            if confidence > 0.4 {
                followingState = .following
            } else if followingState != .following {
                followingState = .lowConfidence
            }
            // If already .following, stay .following even on a low-confidence partial
        }
    }

    func jumpToSentence(_ sentenceIndex: Int) {
        guard sentenceIndex >= 0 && sentenceIndex < document.totalSentences else { return }
        let sentence = document.sentences[sentenceIndex]
        advanceToWord(sentence.wordRange.lowerBound, confidence: 1.0)
        manualSeekSubject.send(currentWordIndex)
    }

    func jumpToBeginning() {
        resetPosition()
    }

    func jumpToEnd() {
        advanceToWord(max(0, document.totalWords - 1), confidence: 1.0)
        manualSeekSubject.send(currentWordIndex)
    }
}
