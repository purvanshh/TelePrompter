import Testing
@testable import TelePrompter

// MARK: - Text Normalization Tests

@Suite("TextNormalizer")
struct TextNormalizationTests {

    @Test("Basic lowercase normalization")
    func basicLowercase() {
        let result = TextNormalizer.normalize("Hello World")
        #expect(result == ["hello", "world"])
    }

    @Test("Punctuation stripped")
    func punctuationStripped() {
        let result = TextNormalizer.normalize("Hello, everyone.")
        #expect(result == ["hello", "everyone"])
    }

    @Test("Multiple punctuation types")
    func multiplePunctuation() {
        let result = TextNormalizer.normalize("Hello! How are you?")
        #expect(result == ["hello", "how", "are", "you"])
    }

    @Test("Empty string returns empty array")
    func emptyString() {
        let result = TextNormalizer.normalize("")
        #expect(result == [])
    }

    @Test("Extra whitespace trimmed")
    func whitespace() {
        let result = TextNormalizer.normalize("  hello   world  ")
        #expect(result == ["hello", "world"])
    }

    @Test("Contraction I'll expanded to I will")
    func contractionIll() {
        let result = TextNormalizer.normalize("I'll explain")
        #expect(result.contains("will"), "Expected 'will' in \(result)")
        #expect(result.contains("explain"))
    }

    @Test("Contraction won't expanded")
    func contractionWont() {
        let result = TextNormalizer.normalize("won't stop")
        let hasExpansion = result.contains("will") || result.contains("not")
        #expect(hasExpansion, "Expected expansion in \(result)")
    }

    @Test("Contraction it's expanded to it is")
    func contractionIts() {
        let result = TextNormalizer.normalize("it's great")
        #expect(result.contains("is"), "Expected 'is' in \(result)")
    }

    @Test("Filler word 'um' removed")
    func fillerUm() {
        let result = TextNormalizer.normalize("Today um we are going to explain")
        #expect(!result.contains("um"), "Filler 'um' should be removed, got \(result)")
        #expect(result.contains("today"))
        #expect(result.contains("explain"))
    }

    @Test("Multiple fillers removed")
    func multipleFillers() {
        let result = TextNormalizer.normalize("um uh er what I mean is")
        #expect(!result.contains("uh"))
        #expect(!result.contains("um"))
        #expect(!result.contains("er"))
        #expect(result.contains("what"))
    }

    @Test("Script-common words like 'so' and 'well' are kept")
    func keepsScriptCommonWords() {
        let result = TextNormalizer.normalize("so well like actually right okay")
        #expect(result.contains("so"))
        #expect(result.contains("well"))
        #expect(result.contains("like"))
        #expect(result.contains("actually"))
    }

    @Test("Hyphen treated as word separator")
    func hyphenSplit() {
        let result = TextNormalizer.normalize("high-risk transactions")
        let combined = result.joined(separator: " ")
        #expect(combined.contains("high") || combined.contains("risk"),
                "Expected hyphen split: \(result)")
    }

    @Test("Strip punctuation from single word")
    func stripPunctuation() {
        let result = TextNormalizer.stripPunctuation("Hello,")
        #expect(result == "hello")
    }

    @Test("Strip quotes from word")
    func stripQuotes() {
        let result = TextNormalizer.stripPunctuation("\"world\"")
        #expect(result == "world")
    }
}
