import Foundation

// MARK: - Script Word

struct ScriptWord: Identifiable, Equatable {
    let id: Int           // global word index across the entire script
    let text: String      // original display text
    let normalized: String // lowercased, no punctuation
    let charOffset: Int   // character offset in original script
    let sentenceIndex: Int
    let paragraphIndex: Int
}

// MARK: - Script Sentence

struct ScriptSentence: Identifiable, Equatable {
    let id: Int           // sentence index
    let text: String      // original display text
    let normalized: String
    let charOffset: Int
    let paragraphIndex: Int
    let wordRange: Range<Int>  // indices into ScriptDocument.words
}

// MARK: - Script Paragraph

struct ScriptParagraph: Identifiable, Equatable {
    let id: Int           // paragraph index
    let text: String
    let charOffset: Int
    let sentenceRange: Range<Int>
    let wordRange: Range<Int>
}

// MARK: - Script Document (fully segmented)

struct ScriptDocument {
    let original: String
    let words: [ScriptWord]
    let sentences: [ScriptSentence]
    let paragraphs: [ScriptParagraph]

    var totalWords: Int { words.count }
    var totalSentences: Int { sentences.count }

    func sentence(containingWord wordIndex: Int) -> ScriptSentence? {
        sentences.first { $0.wordRange.contains(wordIndex) }
    }

    func paragraph(containingWord wordIndex: Int) -> ScriptParagraph? {
        paragraphs.first { $0.wordRange.contains(wordIndex) }
    }

    /// Returns normalized words in the given word-index range
    func normalizedWords(in range: Range<Int>) -> [String] {
        let clamped = range.clamped(to: 0..<words.count)
        return clamped.map { words[$0].normalized }
    }

    /// Returns normalized words around a given position (±radius)
    func normalizedWords(around center: Int, radius: Int) -> [String] {
        let start = max(0, center - radius)
        let end = min(words.count, center + radius)
        return (start..<end).map { words[$0].normalized }
    }

    var isEmpty: Bool { words.isEmpty }
}

// MARK: - Empty document

extension ScriptDocument {
    static let empty = ScriptDocument(original: "", words: [], sentences: [], paragraphs: [])
}
