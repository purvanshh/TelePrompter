import Testing
@testable import TelePrompter

@Suite("FuzzyMatcher")
struct FuzzyMatcherTests {

    // MARK: - Levenshtein distance

    @Test("Identical strings have distance 0")
    func identicalStrings() {
        #expect(FuzzyMatcher.levenshteinDistance("hello", "hello") == 0)
    }

    @Test("One substitution = distance 1")
    func oneSubstitution() {
        #expect(FuzzyMatcher.levenshteinDistance("hello", "hallo") == 1)
    }

    @Test("One insertion = distance 1")
    func oneInsertion() {
        #expect(FuzzyMatcher.levenshteinDistance("helo", "hello") == 1)
    }

    @Test("One deletion = distance 1")
    func oneDeletion() {
        #expect(FuzzyMatcher.levenshteinDistance("hello", "hell") == 1)
    }

    @Test("Empty vs empty = distance 0")
    func emptyVsEmpty() {
        #expect(FuzzyMatcher.levenshteinDistance("", "") == 0)
    }

    @Test("Empty vs string = string length")
    func emptyVsString() {
        #expect(FuzzyMatcher.levenshteinDistance("", "hello") == 5)
    }

    // MARK: - Similarity

    @Test("Identical strings have similarity 1.0")
    func similarityIdentical() {
        #expect(FuzzyMatcher.similarity("hello", "hello") == 1.0)
    }

    @Test("Similar words (detect/detected) have high similarity")
    func similarityPartialMatch() {
        let sim = FuzzyMatcher.similarity("detect", "detected")
        #expect(sim > 0.7, "Expected >0.7, got \(sim)")
    }

    @Test("Very different words have low similarity")
    func similarityLow() {
        let sim = FuzzyMatcher.similarity("hello", "world")
        #expect(sim < 0.5, "Expected <0.5, got \(sim)")
    }

    // MARK: - Sequence scoring

    @Test("Identical token sequence scores high")
    func scoreIdenticalSequence() {
        let tokens = ["hello", "world", "today"]
        let score = FuzzyMatcher.scoreSequence(
            scriptTokens: tokens,
            transcriptTokens: tokens,
            scriptOffset: 0
        )
        #expect(score > 0.8, "Expected >0.8, got \(score)")
    }

    @Test("Completely different sequences score low")
    func scoreMismatch() {
        let script = ["hello", "world", "today"]
        let transcript = ["xyz", "abc", "def"]
        let score = FuzzyMatcher.scoreSequence(
            scriptTokens: script,
            transcriptTokens: transcript,
            scriptOffset: 0
        )
        #expect(score < 0.3, "Expected <0.3, got \(score)")
    }

    @Test("Score tolerates a skipped word")
    func scoreSkippedWord() {
        let script = ["hello", "beautiful", "world"]
        let transcript = ["hello", "world"]
        let score = FuzzyMatcher.scoreSequence(
            scriptTokens: script,
            transcriptTokens: transcript,
            scriptOffset: 0
        )
        #expect(score > 0.3, "Expected >0.3 for skipped word, got \(score)")
    }

    // MARK: - Best alignment

    @Test("Finds exact match position in script")
    func findBestAlignmentExact() {
        let script = ["the", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog"]
        let transcript = ["fox", "jumps", "over"]
        let result = FuzzyMatcher.findBestAlignment(
            scriptTokens: script,
            transcriptTokens: transcript,
            currentIndex: 0,
            searchRadius: script.count
        )
        #expect(result.bestWordIndex == 3, "Expected 3, got \(result.bestWordIndex)")
        #expect(result.confidence > 0.5)
    }

    @Test("Does not jump backward from current position")
    func noBackwardJump() {
        let script = ["one", "two", "three", "four", "five"]
        let transcript = ["four", "five"]
        let result = FuzzyMatcher.findBestAlignment(
            scriptTokens: script,
            transcriptTokens: transcript,
            currentIndex: 3,
            searchRadius: 5
        )
        #expect(result.bestWordIndex >= 3, "Should not jump backward, got \(result.bestWordIndex)")
    }

    // MARK: - N-gram Jaccard

    @Test("Identical token lists have Jaccard 1.0")
    func ngramJaccardIdentical() {
        let tokens = ["hello", "world", "today"]
        let score = FuzzyMatcher.ngramJaccard(tokens, tokens)
        #expect(score == 1.0)
    }

    @Test("Completely different tokens have Jaccard 0.0")
    func ngramJaccardNoOverlap() {
        let a = ["hello", "world"]
        let b = ["xyz", "abc"]
        let score = FuzzyMatcher.ngramJaccard(a, b)
        #expect(score == 0.0)
    }

    @Test("Partial overlap gives intermediate Jaccard score")
    func ngramJaccardPartial() {
        let a = ["hello", "world", "today"]
        let b = ["world", "today", "tomorrow"]
        let score = FuzzyMatcher.ngramJaccard(a, b)
        #expect(score > 0 && score < 1, "Expected 0 < score < 1, got \(score)")
    }
}
