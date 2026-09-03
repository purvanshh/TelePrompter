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
        var moveThreshold: Double = 0.28
        var backtrackThreshold: Double = 0.65
        /// 0 = Strict, 1 = Lenient. Affects threshold, radius, min tokens, jump caps.
        var sensitivity: Double = 0.5
        var backtrackPenalty: Double = 0.35
        /// Min words in transcript before attempting alignment (overridden by sensitivity)
        var minTranscriptWords: Int = 1
        /// Max number of confirmed tokens to retain across sessions (rolling window)
        var confirmedTokenCap: Int = 40
        /// Consecutive agreeing partials required before committing a large backward snap
        var partialStabilityHits: Int = 2
        /// How close consecutive partial candidates must be (in words) to count as agreement
        var partialAgreementWindow: Int = 5
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

    /// Local search radius: Strict ≈ 60, Normal ≈ 100, Lenient ≈ 140
    private var effectiveSearchRadius: Int {
        Int(60.0 + config.sensitivity * 80.0)
    }

    /// Move confidence threshold: Strict ≈ 0.34, Normal ≈ 0.28, Lenient ≈ 0.22
    private var effectiveMoveThreshold: Double {
        max(0.20, config.moveThreshold + (0.5 - config.sensitivity) * 0.16)
    }

    /// Min tokens before aligning
    private var effectiveMinWords: Int {
        config.sensitivity < 0.33 ? 2 : 1
    }

    /// Uniqueness margin for large/global jumps
    private var effectiveUniquenessMargin: Double {
        max(0.015, 0.06 - config.sensitivity * 0.04)
    }

    /// Max words a single partial may advance locally
    private var maxPartialJump: Int {
        if config.sensitivity < 0.33 { return 28 }
        if config.sensitivity < 0.66 { return 45 }
        return 70
    }

    /// Max words a final result may advance locally
    private var maxFinalJump: Int {
        if config.sensitivity < 0.33 { return 50 }
        if config.sensitivity < 0.66 { return 90 }
        return 140
    }

    private static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "to", "of", "in", "on", "at",
        "for", "is", "are", "was", "were", "be", "been", "am", "i", "you",
        "we", "they", "he", "she", "it", "this", "that", "with", "as", "by",
        "from", "my", "our", "your", "their"
    ]

    private func contentWordCount(in tokens: [String]) -> Int {
        tokens.filter { !Self.stopwords.contains($0) && $0.count > 2 }.count
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

        // Short recent tip → tracks live speech (less lag).
        // Longer window → used to relocate when the reader jumps sections.
        let tipTokens = Array(tokens.suffix(min(8, tokens.count)))
        let relocateTokens = Array(tokens.suffix(min(14, tokens.count)))
        let currentTokenIndex = tokenIndex(forDisplayWord: currentWordIndex)

        // 1) Local catch-up around the current position (fast, low lag)
        let local = FuzzyMatcher.findBestAlignment(
            scriptTokens: scriptTokens,
            transcriptTokens: tipTokens,
            currentIndex: currentTokenIndex,
            searchRadius: effectiveSearchRadius,
            backtrackPenalty: 0.35,
            forwardPenaltyPerWord: 0.015,
            minForwardFactor: 0.65,
            lookBehindFraction: 0.35
        )

        let localCandidate = displayCandidate(from: local)

        // 2) Global relocate when the speaker starts reading from somewhere else.
        // Skip when local tracking is healthy to keep long scripts responsive.
        var relocate: FuzzyMatcher.AlignmentResult? = nil
        let enoughForRelocate = relocateTokens.count >= 4 && contentWordCount(in: relocateTokens) >= 2
        let localLooksStuck = local.confidence < effectiveMoveThreshold + 0.08
            || abs(localCandidate - currentWordIndex) <= 2
            || stalledUpdates >= 1
        if enoughForRelocate && localLooksStuck {
            relocate = FuzzyMatcher.findBestAlignmentGlobal(
                scriptTokens: scriptTokens,
                transcriptTokens: relocateTokens,
                currentIndex: currentTokenIndex,
                backtrackPenalty: 0.12
            )
        }

        var threshold = effectiveMoveThreshold
        if stalledUpdates >= 2 { threshold -= 0.05 }
        if !isPartial { threshold -= 0.03 }

        let relocateCandidate = relocate.map { displayCandidate(from: $0) }

        let useRelocate: Bool = {
            guard let relocate, let relocateCandidate else { return false }
            let far = abs(relocateCandidate - currentWordIndex) > 12
            let unique = relocate.scoreMargin >= max(effectiveUniquenessMargin, 0.04)
            let strong = relocate.confidence >= threshold + 0.05
            let better = relocate.confidence + 0.05 >= local.confidence
            // Prefer relocate over local when local stayed near current but speech matches elsewhere
            let localStayedNear = abs(localCandidate - currentWordIndex) <= 8
            return far && unique && strong && (better || localStayedNear)
        }()

        let chosen = useRelocate ? relocate! : local
        let confidence = chosen.confidence
        lastConfidence = confidence
        let matchTokens = useRelocate ? relocateTokens : tipTokens

        guard confidence >= threshold else {
            noteStall()
            emitUpdate(wordIndex: currentWordIndex, confidence: confidence,
                       transcript: matchTokens.joined(separator: " "))
            return
        }

        var candidate = displayCandidate(from: chosen)
        // Small lead bias so the highlight stays with live speech (ASR lags a bit).
        if candidate >= currentWordIndex {
            let lead = isPartial ? 1 : 0
            candidate = min(document.totalWords - 1, candidate + lead)
        }

        let distance = candidate - currentWordIndex
        let absDistance = abs(distance)

        // Uniqueness gate for large non-relocate leaps only
        if !useRelocate && absDistance > 20
            && chosen.scoreMargin < effectiveUniquenessMargin
            && stalledUpdates < 3 {
            noteStall()
            emitUpdate(wordIndex: currentWordIndex, confidence: confidence,
                       transcript: matchTokens.joined(separator: " "))
            return
        }

        var accepted: Int? = nil

        if useRelocate {
            // Distinctive phrase found elsewhere — jump there immediately.
            accepted = candidate
        } else if distance >= 0 {
            let maxJump = isPartial ? maxPartialJump : maxFinalJump
            if distance <= maxJump {
                accepted = candidate
            } else {
                // Chunk catch-up toward the true match (don't stay frozen far behind).
                accepted = currentWordIndex + maxJump
            }
        } else if absDistance <= 12 && confidence >= config.backtrackThreshold * 0.9 {
            accepted = candidate
        } else if absDistance <= 40 && chosen.scoreMargin >= effectiveUniquenessMargin
                    && confidence >= threshold + 0.08 {
            // Distinctive match behind current (started reading earlier section)
            accepted = candidate
        }

        if accepted == nil && stalledUpdates >= 3 && distance > 0 {
            accepted = min(candidate, currentWordIndex + 12)
        }

        guard let target = accepted else {
            noteStall()
            emitUpdate(wordIndex: currentWordIndex, confidence: confidence,
                       transcript: matchTokens.joined(separator: " "))
            return
        }

        // No multi-hit wait for forward/relocate — lag is worse than occasional nudge.
        // Only require agreement for large backward snaps.
        if isPartial && target < currentWordIndex - 4 {
            if let pending = pendingCandidate,
               abs(target - pending) <= config.partialAgreementWindow {
                pendingHits += 1
                pendingCandidate = target
            } else {
                pendingCandidate = target
                pendingHits = 1
            }
            guard pendingHits >= config.partialStabilityHits else {
                noteStall()
                emitUpdate(wordIndex: currentWordIndex, confidence: confidence,
                           transcript: matchTokens.joined(separator: " "))
                return
            }
        } else {
            clearPending()
        }

        currentWordIndex = target
        if let sentence = document.sentence(containingWord: currentWordIndex) {
            currentSentenceIndex = sentence.id
        }
        noteProgress()

        emitUpdate(wordIndex: currentWordIndex, confidence: confidence,
                   transcript: matchTokens.joined(separator: " "))
    }

    private func displayCandidate(from result: FuzzyMatcher.AlignmentResult) -> Int {
        let matchStart = result.bestWordIndex
        let matchEndToken = min(
            scriptTokens.count - 1,
            matchStart + max(0, result.matchedTokenCount - 1)
        )
        return displayWord(forToken: matchEndToken)
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
