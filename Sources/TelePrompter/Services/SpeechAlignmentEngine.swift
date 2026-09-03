import Foundation
import Combine

// MARK: - AlignmentUpdate

struct AlignmentUpdate {
    let wordIndex: Int
    let sentenceIndex: Int
    let confidence: Double
    let transcriptUsed: String
}

// MARK: - SpeechAlignmentEngine
//
// Apple's SFSpeechRecognizer sends a *cumulative* transcript on every callback:
//   partial 1: "Hello"
//   partial 2: "Hello everyone"
//   partial 3: "Hello everyone today"
//   final:     "Hello everyone today I want to"
//
// A new recognition session starts after each final result. So:
//   - We keep a `confirmedWordCount` tracking how many words were in the
//     most recent final result, so we know where the new session started.
//   - For alignment we use only the LATEST partial/final text of the current session,
//     matched against the script starting from the current position.

final class SpeechAlignmentEngine {

    // MARK: - Configuration

    struct Config {
        var searchRadius: Int = 80
        var moveThreshold: Double = 0.30
        var backtrackThreshold: Double = 0.65
        var sensitivity: Double = 0.5
        var backtrackPenalty: Double = 0.40
        /// Min words in transcript before attempting alignment
        var minTranscriptWords: Int = 1
        /// Max number of confirmed tokens to retain across sessions (rolling window)
        var confirmedTokenCap: Int = 40
    }

    var config: Config

    // MARK: - State

    private(set) var currentWordIndex: Int = 0
    private(set) var currentSentenceIndex: Int = 0
    private(set) var lastConfidence: Double = 0

    /// All confirmed (final) normalized tokens across sessions, rolling window
    private var confirmedTokens: [String] = []
    /// The normalized tokens from the current (in-progress) session's latest result
    private var currentSessionTokens: [String] = []
    /// Count of confirmed tokens that have already been used for position updates
    private var lastAlignedConfirmedCount: Int = 0

    private var document: ScriptDocument = .empty

    /// Flat token stream used for matching. Built from each display word's
    /// normalized text split into individual tokens (e.g. a contraction such as
    /// "I'll" expands to the two tokens "i" and "will"), so it matches the
    /// tokenization that transcripts go through in TextNormalizer.
    private var scriptTokens: [String] = []
    /// For each flat token, the display-word index it belongs to.
    private var tokenWordIndex: [Int] = []
    /// The first flat-token index of each display word (for index round-tripping).
    private var wordStartToken: [Int] = []

    private let updateSubject = PassthroughSubject<AlignmentUpdate, Never>()
    var updatePublisher: AnyPublisher<AlignmentUpdate, Never> {
        updateSubject.eraseToAnyPublisher()
    }

    // MARK: - Lifecycle

    init(config: Config = Config()) {
        self.config = config
    }

    func load(document: ScriptDocument) {
        self.document = document
        buildTokenStream(document)
        reset()
    }

    /// Build a flat, normalized token stream from the script's display words.
    ///
    /// Alignment must run on a token stream produced by the same normalizer used
    /// on transcripts (TextNormalizer). The parser stores one `ScriptWord` per
    /// display word, but a single display word can normalize into several tokens
    /// (contractions like "I'll" → ["i","will"], hyphenated words like
    /// "high-risk" → ["high","risk"]). If we matched against the raw per-word
    /// strings, "i will" (one entry) would never align with the transcript's two
    /// separate tokens "i" and "will", and voice follow would fail on real scripts.
    private func buildTokenStream(_ document: ScriptDocument) {
        scriptTokens = []
        tokenWordIndex = []
        wordStartToken = []

        for (wordIndex, word) in document.words.enumerated() {
            let tokens = word.normalized.split(whereSeparator: { $0 == " " || $0 == "\n" })
            wordStartToken.append(scriptTokens.count)
            for token in tokens where !token.isEmpty {
                scriptTokens.append(String(token))
                tokenWordIndex.append(wordIndex)
            }
        }
    }

    /// Flat-token index corresponding to the given display-word index.
    private func tokenIndex(forDisplayWord wordIndex: Int) -> Int {
        guard !wordStartToken.isEmpty else { return 0 }
        return wordStartToken[Swift.min(Swift.max(0, wordIndex), wordStartToken.count - 1)]
    }

    /// Display-word index corresponding to the given flat-token index.
    private func displayWord(forToken tokenIndex: Int) -> Int {
        guard !tokenWordIndex.isEmpty else { return 0 }
        return tokenWordIndex[Swift.min(Swift.max(0, tokenIndex), tokenWordIndex.count - 1)]
    }

    func reset() {
        currentWordIndex = 0
        currentSentenceIndex = 0
        lastConfidence = 0
        confirmedTokens = []
        currentSessionTokens = []
        lastAlignedConfirmedCount = 0
    }

    // MARK: - Process transcript
    //
    // Call this with every recognition callback.
    // `text`    = the CUMULATIVE transcript for the current recognition session
    // `isFinal` = true when Apple closes the session (after ~60 sec or silence)

    func processTranscript(_ text: String, isFinal: Bool) {
        guard !document.isEmpty else { return }

        let tokens = TextNormalizer.normalize(text)

        if isFinal {
            // On final, these tokens represent the complete utterance for this session.
            // Use ONLY this session's tokens (not accumulated confirmed) for alignment —
            // the engine's currentWordIndex already points past previously confirmed text.
            currentSessionTokens = tokens
            alignAndEmit(tokens: tokens, isPartial: false)

            // Now commit to confirmed buffer so next session can anchor correctly
            confirmedTokens.append(contentsOf: tokens)
            // Rolling cap — use configurable limit
            if confirmedTokens.count > config.confirmedTokenCap {
                confirmedTokens = Array(confirmedTokens.suffix(config.confirmedTokenCap))
            }
            currentSessionTokens = []
            lastAlignedConfirmedCount = confirmedTokens.count
        } else {
            // Partial: Apple sends cumulative text for the current session.
            // Use ONLY the current session tokens for alignment —
            // confirmed tokens' position is already captured in currentWordIndex.
            currentSessionTokens = tokens

            guard tokens.count >= config.minTranscriptWords else { return }
            alignAndEmit(tokens: tokens, isPartial: true)
        }
    }

    // MARK: - Manual position control

    func setPosition(wordIndex: Int) {
        guard wordIndex >= 0 && wordIndex < document.totalWords else { return }
        currentWordIndex = wordIndex
        if let sentence = document.sentence(containingWord: wordIndex) {
            currentSentenceIndex = sentence.id
        }
        // Clear buffers when manually repositioned so next speech starts fresh
        confirmedTokens = []
        currentSessionTokens = []
        lastAlignedConfirmedCount = 0
        emitUpdate(wordIndex: wordIndex, confidence: 1.0, transcript: "")
    }

    // MARK: - Core alignment

    private func alignAndEmit(tokens: [String], isPartial: Bool) {
        guard !tokens.isEmpty, !scriptTokens.isEmpty else { return }

        // Use the trailing N tokens for matching (the most recently spoken words)
        let matchTokens = Array(tokens.suffix(20))

        // Alignment works in flat-token space, so anchor the search at the flat
        // token index of the current display word.
        let currentTokenIndex = tokenIndex(forDisplayWord: currentWordIndex)

        let result = FuzzyMatcher.findBestAlignment(
            scriptTokens: scriptTokens,
            transcriptTokens: matchTokens,
            currentIndex: currentTokenIndex,
            searchRadius: config.searchRadius,
            backtrackPenalty: config.backtrackPenalty
        )

        // Threshold: partials need less confidence to keep things responsive,
        // but we use a higher bar to prevent wild jumps
        let threshold: Double
        if isPartial {
            threshold = config.moveThreshold * (1.0 - config.sensitivity * 0.4)
        } else {
            threshold = config.moveThreshold * (1.0 - config.sensitivity * 0.5)
        }

        let confidence = result.confidence
        lastConfidence = confidence

        guard confidence >= threshold else {
            // Not confident enough — stay put, but still emit so the UI shows "low confidence"
            emitUpdate(wordIndex: currentWordIndex, confidence: confidence,
                       transcript: matchTokens.joined(separator: " "))
            return
        }

        // bestWordIndex is the START of the match in token space.
        // Advance to the END of the matched section — that's where the speaker is NOW.
        let matchStart = result.bestWordIndex
        let matchEndToken = min(scriptTokens.count - 1, matchStart + result.matchedTokenCount)

        // Map token positions back to display-word indices for the UI/state.
        let candidate = displayWord(forToken: matchEndToken)
        let distance  = candidate - currentWordIndex  // positive = forward

        // Movement rules:
        if distance >= 0 {
            // Forward movement — always allowed
            currentWordIndex = candidate
        } else if abs(distance) <= 8 && confidence >= config.backtrackThreshold {
            // Small backward movement with high confidence (e.g., user repeated a sentence)
            currentWordIndex = candidate
        }
        // Else: ignore backward movement — the user likely triggered a false match

        if let sentence = document.sentence(containingWord: currentWordIndex) {
            currentSentenceIndex = sentence.id
        }

        emitUpdate(wordIndex: currentWordIndex, confidence: confidence,
                   transcript: matchTokens.joined(separator: " "))
    }

    // MARK: - Helpers

    private func emitUpdate(wordIndex: Int, confidence: Double, transcript: String) {
        let update = AlignmentUpdate(
            wordIndex: wordIndex,
            sentenceIndex: currentSentenceIndex,
            confidence: confidence,
            transcriptUsed: transcript
        )
        updateSubject.send(update)
    }
}
