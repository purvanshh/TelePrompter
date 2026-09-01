import Testing
@testable import TelePrompter
import Foundation

@Suite("ScriptParser")
struct ScriptParserTests {

    // MARK: - Basic parsing

    @Test("Parses words from plain text")
    func parsesWords() {
        let doc = ScriptParser.parse(text: "Hello world today.")
        #expect(doc.totalWords > 0)
        #expect(doc.words.first?.text == "Hello")
    }

    @Test("Parses multiple paragraphs separated by blank lines")
    func parsesMultipleParagraphs() {
        let text = "First paragraph here.\n\nSecond paragraph here."
        let doc = ScriptParser.parse(text: text)
        #expect(doc.paragraphs.count == 2, "Expected 2 paragraphs, got \(doc.paragraphs.count)")
    }

    @Test("Empty text produces empty document")
    func emptyTextProducesEmptyDocument() {
        let doc = ScriptParser.parse(text: "")
        #expect(doc.isEmpty)
        #expect(doc.totalWords == 0)
        #expect(doc.totalSentences == 0)
    }

    @Test("Whitespace-only text produces empty document")
    func whitespaceOnlyProducesEmpty() {
        let doc = ScriptParser.parse(text: "   \n\n   ")
        #expect(doc.isEmpty)
    }

    // MARK: - Sentence segmentation

    @Test("Detects sentence boundaries")
    func sentenceCount() {
        let text = "Hello. How are you? I am fine."
        let doc = ScriptParser.parse(text: text)
        #expect(doc.totalSentences >= 2, "Expected ≥2 sentences, got \(doc.totalSentences)")
    }

    // MARK: - Word indices

    @Test("Word IDs are sequential starting at 0")
    func wordIndicesAreSequential() {
        let doc = ScriptParser.parse(text: "One two three four five.")
        for (i, word) in doc.words.enumerated() {
            #expect(word.id == i, "Word index mismatch at \(i): \(word.id)")
        }
    }

    // MARK: - Sentence word ranges

    @Test("Sentence word ranges are within document bounds")
    func sentenceWordRangesAreValid() {
        let text = "First sentence here. Second sentence here."
        let doc = ScriptParser.parse(text: text)
        for sentence in doc.sentences {
            #expect(sentence.wordRange.upperBound <= doc.totalWords,
                    "Sentence range out of bounds: \(sentence.wordRange)")
            #expect(sentence.wordRange.lowerBound >= 0)
        }
    }

    // MARK: - Normalized words

    @Test("Normalized words are lowercase")
    func normalizedWordsAreLowercase() {
        let doc = ScriptParser.parse(text: "Hello World Test.")
        for word in doc.words {
            let norm = word.normalized
            #expect(norm == norm.lowercased(), "'\(norm)' should be lowercase")
        }
    }

    @Test("Normalized words contain no punctuation")
    func normalizedWordsHaveNoPunctuation() {
        let doc = ScriptParser.parse(text: "Hello, world! How are you?")
        for word in doc.words {
            #expect(!word.normalized.contains(","), "Found comma in '\(word.normalized)'")
            #expect(!word.normalized.contains("!"), "Found ! in '\(word.normalized)'")
        }
    }

    // MARK: - Look-up helpers

    @Test("sentence(containingWord:) returns correct sentence")
    func sentenceContainingWord() {
        let doc = ScriptParser.parse(text: "First sentence. Second sentence.")
        let sentence = doc.sentence(containingWord: 0)
        #expect(sentence != nil)
        #expect(sentence?.id == 0)
    }

    @Test("paragraph(containingWord:) returns correct paragraph")
    func paragraphContainingWord() {
        let doc = ScriptParser.parse(text: "First paragraph.\n\nSecond paragraph.")
        let para = doc.paragraph(containingWord: 0)
        #expect(para != nil)
        #expect(para?.id == 0)
    }

    // MARK: - Long script

    @Test("500-word script parses correctly")
    func longScriptDoesNotCrash() {
        let words = (0..<500).map { "word\($0)" }
        let sentences = stride(from: 0, to: 500, by: 10).map { i in
            words[i..<min(i+10, 500)].joined(separator: " ") + "."
        }
        let text = sentences.joined(separator: "\n\n")
        let doc = ScriptParser.parse(text: text)
        #expect(doc.totalWords == 500, "Expected 500 words, got \(doc.totalWords)")
    }

    // MARK: - Markdown import

    @Test("Markdown headers and bold markers are stripped")
    func markdownStripHeaders() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).md")
        let md = "# Title\n\nThis is **bold** text and *italic* text.\n\n[Link](http://example.com)"
        try md.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = try ScriptParser.importFile(url: tmp)
        #expect(!result.contains("#"), "Should strip markdown headers")
        #expect(!result.contains("**"), "Should strip bold markers")
        #expect(result.contains("bold"), "Should keep text content")
    }

    // MARK: - TXT import

    @Test("TXT file import works")
    func txtImport() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).txt")
        let content = "Hello world. This is a test."
        try content.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = try ScriptParser.importFile(url: tmp)
        #expect(result == content)
    }
}
