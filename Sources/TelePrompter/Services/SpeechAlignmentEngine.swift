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
// A new recognition session starts after each final result. Alignment uses only
// the current session's tokens, anchored at currentWordIndex, with stability
// gates so short/ambiguous partials cannot thrash the cursor.

final class SpeechAlignmentEngine {

    // MARK: - Configuration

    struct Config {
        var searchRadius: Int = 80
        var moveThreshold: Double = 0.30
        var backtrackThreshold: Double = 0.70
        /// 0 = Strict, 1 = Lenient. Affects threshold, radius, min tokens, jump caps.
        var sensitivity: Double = 0.5
        var backtrackPenalty: Double = 0.45
        /// Min words in transcript before attempting alignment (overridden by sensitivity)
        var minTranscriptWords: Int = 2
        /// Max number of confirmed tokens to retain across sessions (rolling window)
        var confirmedTokenCap: Int = 40
        /// Consecutive agreeing partials required before committing a *large ambiguous* jump
        var partialStabilityHits: Int = 2
        /// How close consecutive partial candidates must be (in words) to count as agreement
        var partialAgreementWindow: Int = 4
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

    /// Pending partial candidate waiting for consecutive agreement
    private var pendingCandidate: Int? = nil
    private var pendingHits: Int = 0
    /// Consecutive updates that failed to move — used to force catch-up past hard words
    private var stalledUpdates: Int = 0

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

    // MARK: - Sensitivity-derived knobs

    /// Effective search radius: Strict ≈ 45, Normal ≈ 70, Lenient ≈ 100
    private var effectiveSearchRadius: Int {
        Int(45.0 + config.sensitivity * 55.0)
    }

    /// Move confidence threshold: Strict ≈ 0.40, Normal ≈ 0.32, Lenient ≈ 0.26
    private var effectiveMoveThreshold: Double {
        max(0.24, config.moveThreshold + (0.5 - config.sensitivity) * 0.20)
    }

    /// Min tokens before aligning: Strict 3, Normal 2, Lenient 2
    private var effectiveMinWords: Int {
        if config.sensitivity < 0.33 { return 3 }
        return 2
    }

    /// Required uniqueness margin (best − second-best): only applied to large jumps
    private var effectiveUniquenessMargin: Double {
        max(0.02, 0.08 - config.sensitivity * 0.05)
    }

    /// Max words a single partial may advance — roomy so catch-up stays responsive
    private var maxPartialJump: Int {
        if config.sensitivity < 0.33 { return 14 }
        if config.sensitivity < 0.66 { return 22 }
        return 30
    }

    /// Max words a final result may advance
    private var maxFinalJump: Int {
        if config.sensitivity < 0.33 { return 35 }
        if config.sensitivity < 0.66 { return 50 }
        return 70
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
        clearPending()
        stalledUpdates = 0
    }

    private func clearPending() {
        pendingCandidate = nil
        pendingHits = 0
    }

    private func noteStall() {
        stalledUpdates += 1
    }

    private func noteProgress() {
        stalledUpdates = 0
        clearPending()
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
            currentSessionTokens = tokens
            alignAndEmit(tokens: tokens, isPartial: false)

            confirmedTokens.append(contentsOf: tokens)
            if confirmedTokens.count > config.confirmedTokenCap {
                confirmedTokens = Array(confirmedTokens.suffix(config.confirmedTokenCap))
            }
            currentSessionTokens = []
            lastAlignedConfirmedCount = confirmedTokens.count
            clearPending()
        } else {
            currentSessionTokens = tokens
            guard tokens.count >= effectiveMinWords else { return }
            alignAndEmit(tokens: tokens, isPartial: true)
        }
    }

    // MARK: - Manual position control

    /// Sync engine position to a user-selected word. Does not publish an update —
    /// the UI already owns the visible cursor.
    func setPosition(wordIndex: Int) {
        guard wordIndex >= 0 && wordIndex < document.totalWords else { return }
        currentWordIndex = wordIndex
        if let sentence = document.sentence(containingWord: wordIndex) {
            currentSentenceIndex = sentence.id
        }
        confirmedTokens = []
        currentSessionTokens = []
        lastAlignedConfirmedCount = 0
        clearPending()
        stalledUpdates = 0
        lastConfidence = 1.0
    }

    // MARK: - Core alignment

    private func alignAndEmit(tokens: [String], isPartial: Bool) {
        guard !tokens.isEmpty, !scriptTokens.isEmpty else { return }

        // Prefer recently spoken words; keep enough context for catch-up when lagging.
        let suffixLen = isPartial ? min(18, tokens.count) : min(28, tokens.count)
        let matchTokens = Array(tokens.suffix(suffixLen))

        let currentTokenIndex = tokenIndex(forDisplayWord: currentWordIndex)

        let result = FuzzyMatcher.findBestAlignment(
            scriptTokens: scriptTokens,
            transcriptTokens: matchTokens,
            currentIndex: currentTokenIndex,
            searchRadius: effectiveSearchRadius,
            backtrackPenalty: config.backtrackPenalty,
            forwardPenaltyPerWord: 0.045,
            minForwardFactor: 0.35
        )

        var threshold = effectiveMoveThreshold
        // When stalled on a hard word, lower the bar so we can skip past it.
        if stalledUpdates >= 3 {
            threshold -= 0.06
        }
        if isPartial {
            threshold += 0.02
        } else {
            threshold -= 0.04
        }

        let confidence = result.confidence
        lastConfidence = confidence

        guard confidence >= threshold else {
            noteStall()
            emitUpdate(wordIndex: currentWordIndex, confidence: confidence,
                       transcript: matchTokens.joined(separator: " "))
            return
        }

        let matchStart = result.bestWordIndex
        let matchEndToken = min(scriptTokens.count - 1, matchStart + max(0, result.matchedTokenCount - 1))
        let candidate = displayWord(forToken: matchEndToken)
        let distance = candidate - currentWordIndex
        let absDistance = abs(distance)

        // Uniqueness only gates large leaps — small/medium forward catch-up stays responsive.
        let needsStrongUniqueness = absDistance > 14
        if needsStrongUniqueness && result.scoreMargin < effectiveUniquenessMargin && stalledUpdates < 4 {
            noteStall()
            emitUpdate(wordIndex: currentWordIndex, confidence: confidence,
                       transcript: matchTokens.joined(separator: " "))
            return
        }

        // Movement policy — prefer catching up when the speaker is ahead.
        var accepted: Int? = nil

        if distance >= 0 {
            let maxJump = isPartial ? maxPartialJump : maxFinalJump
            if distance <= maxJump {
                accepted = candidate
            } else if confidence >= threshold + 0.08 {
                // Speaker got far ahead — catch up in chunks instead of staying stuck.
                accepted = currentWordIndex + maxJump
            }
        } else if absDistance <= 6 && confidence >= config.backtrackThreshold
                    && result.scoreMargin >= effectiveUniquenessMargin * 0.4 {
            accepted = candidate
        }

        // Stuck recovery: if we keep failing to move but ASR matches somewhere ahead,
        // nudge forward by a few words so hard tokens like "checkout" don't freeze us.
        if accepted == nil && stalledUpdates >= 4 && distance > 0 {
            accepted = min(candidate, currentWordIndex + 6)
        }

        guard let target = accepted else {
            noteStall()
            emitUpdate(wordIndex: currentWordIndex, confidence: confidence,
                       transcript: matchTokens.joined(separator: " "))
            return
        }

        // Stability: forward catch-up commits immediately. Only large ambiguous jumps wait.
        if isPartial {
            let forwardDistance = target - currentWordIndex
            let needsHits: Int
            if forwardDistance <= 10 || stalledUpdates >= 3 {
                needsHits = 1
            } else if forwardDistance <= 18 {
                needsHits = 1
            } else {
                needsHits = config.partialStabilityHits
            }

            if needsHits > 1 {
                if let pending = pendingCandidate,
                   abs(target - pending) <= config.partialAgreementWindow {
                    pendingHits += 1
                    pendingCandidate = target
                } else {
                    pendingCandidate = target
                    pendingHits = 1
                }
                guard pendingHits >= needsHits else {
                    noteStall()
                    emitUpdate(wordIndex: currentWordIndex, confidence: confidence,
                               transcript: matchTokens.joined(separator: " "))
                    return
                }
            }
        } else {
            clearPending()
        }

        // Never move backward accidentally when catching up after a stall
        if target < currentWordIndex && stalledUpdates >= 2 {
            noteStall()
            emitUpdate(wordIndex: currentWordIndex, confidence: confidence,
                       transcript: matchTokens.joined(separator: " "))
            return
        }

        currentWordIndex = target
        if let sentence = document.sentence(containingWord: currentWordIndex) {
            currentSentenceIndex = sentence.id
        }
        noteProgress()

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
