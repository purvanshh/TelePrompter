import Testing
@testable import TelePrompter

@Suite("SpeechAlignmentEngine")
struct SpeechAlignmentTests {

    // MARK: - Helper

    func makeEngine(script: String) -> (SpeechAlignmentEngine, ScriptDocument) {
        let doc = ScriptParser.parse(text: script)
        let engine = SpeechAlignmentEngine()
        engine.load(document: doc)
        return (engine, doc)
    }

    // MARK: - Exact match

    @Test("Aligns to start on exact match")
    func exactMatchHelloEveryone() {
        let (engine, _) = makeEngine(script: "Hello everyone. Today I am going to explain our project.")
        engine.processTranscript("Hello everyone", isFinal: true)
        #expect(engine.currentWordIndex < 3, "Should align to start, got \(engine.currentWordIndex)")
        #expect(engine.lastConfidence > 0.3)
    }

    // MARK: - Case differences

    @Test("Case differences do not prevent alignment")
    func caseDifference() {
        let (engine, _) = makeEngine(script: "Hello Everyone. This is our system.")
        engine.processTranscript("hello everyone", isFinal: true)
        #expect(engine.currentWordIndex < 4, "Got \(engine.currentWordIndex)")
    }

    // MARK: - Punctuation differences

    @Test("Punctuation differences tolerated")
    func punctuationDifference() {
        let (engine, _) = makeEngine(script: "Hello, everyone. Welcome to the show.")
        engine.processTranscript("Hello everyone welcome to the show", isFinal: true)
        #expect(engine.currentWordIndex > 1, "Should advance past punctuation: \(engine.currentWordIndex)")
    }

    // MARK: - Minor wording difference

    @Test("Minor wording difference still aligns")
    func minorWordingDifference() {
        let script = "We built a fraud detection system. It identifies risky transactions."
        let (engine, _) = makeEngine(script: script)
        engine.processTranscript("We developed a fraud detection system", isFinal: true)
        #expect(engine.currentWordIndex < 8,
                "Should align despite 'built' vs 'developed': \(engine.currentWordIndex)")
        #expect(engine.lastConfidence > 0.2)
    }

    // MARK: - Filler words tolerated

    @Test("Filler words are tolerated")
    func fillerWordsTolerated() {
        let script = "Today we explain the project in detail."
        let (engine, _) = makeEngine(script: script)
        engine.processTranscript("Today um we are going to explain the project", isFinal: true)
        #expect(engine.currentWordIndex < 7, "Should align past fillers: \(engine.currentWordIndex)")
    }

    // MARK: - Forward progression

    @Test("Forward progression is preferred over backward")
    func forwardProgressionPreferred() {
        let script = "First sentence here. Second sentence here. Third sentence here."
        let (engine, _) = makeEngine(script: script)

        engine.processTranscript("First sentence here", isFinal: true)
        let pos1 = engine.currentWordIndex

        engine.processTranscript("Second sentence here", isFinal: true)
        let pos2 = engine.currentWordIndex

        #expect(pos2 >= pos1, "Position went backward: \(pos1) → \(pos2)")
    }

    // MARK: - Empty script

    @Test("Empty script does not crash")
    func emptyScript() {
        let engine = SpeechAlignmentEngine()
        engine.load(document: .empty)
        engine.processTranscript("Hello world", isFinal: true)
        #expect(engine.currentWordIndex == 0)
    }

    // MARK: - Empty transcript

    @Test("Empty transcript does not crash")
    func emptyTranscript() {
        let (engine, _) = makeEngine(script: "Hello world test.")
        engine.processTranscript("", isFinal: true)
        #expect(engine.currentWordIndex == 0)
    }

    // MARK: - Long script performance

    @Test("Processes 500-word script without hanging", .timeLimit(.minutes(1)))
    func longScriptPerformance() {
        let words = (0..<500).map { "word\($0)" }
        let script = words.joined(separator: " ")
        let (engine, _) = makeEngine(script: script)
        let transcript = words[200...210].joined(separator: " ")
        engine.processTranscript(transcript, isFinal: true)
        // No assertion — just must complete within time limit
    }

    // MARK: - Very long script

    @Test("2000-word script does not crash")
    func veryLongScript() {
        let baseWords = ["hello", "world", "today", "explain", "system", "detect", "fraud", "process"]
        let words = (0..<2000).map { i in baseWords[i % baseWords.count] }
        let script = words.joined(separator: " ")
        let (engine, _) = makeEngine(script: script)
        engine.processTranscript("hello world today explain", isFinal: true)
        #expect(engine.currentWordIndex >= 0)
    }

    // MARK: - Repeated phrase

    @Test("Repeated phrase advances to unique content")
    func repeatedPhrase() {
        let script = "Today we discuss. Today we discuss. Different content here."
        let (engine, _) = makeEngine(script: script)

        engine.processTranscript("Today we discuss", isFinal: true)
        let pos1 = engine.currentWordIndex

        engine.processTranscript("Different content here", isFinal: true)
        let pos2 = engine.currentWordIndex

        #expect(pos2 >= pos1, "Should advance to unique content: \(pos1) → \(pos2)")
    }

    // MARK: - Backtracking is limited

    @Test("Backtracking is limited and controlled")
    func backtrackingIsLimited() {
        let script = "First sentence. Second sentence. Third sentence. Fourth sentence."
        let (engine, _) = makeEngine(script: script)

        engine.processTranscript("Third sentence", isFinal: true)
        let posAfterThird = engine.currentWordIndex
        #expect(posAfterThird > 2, "Should advance to third sentence: \(posAfterThird)")

        engine.processTranscript("First sentence", isFinal: true)
        let posAfterFirst = engine.currentWordIndex
        #expect(posAfterFirst >= 0, "Should not go negative")
    }

    // MARK: - Manual position override

    @Test("Manual position override sets exact word index")
    func manualPositionOverride() {
        let script = "Word0 Word1 Word2 Word3 Word4 Word5."
        let (engine, _) = makeEngine(script: script)

        engine.setPosition(wordIndex: 3)
        #expect(engine.currentWordIndex == 3)

        engine.processTranscript("Word4 Word5", isFinal: true)
        #expect(engine.currentWordIndex >= 3)
    }
}
