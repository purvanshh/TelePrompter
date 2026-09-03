import Foundation

// MARK: - TextNormalizer
// Converts text to a canonical form for speech-to-script matching.
// IMPORTANT: Normalization is for MATCHING only. Display text is never altered.

struct TextNormalizer {

    // MARK: - Contraction expansion table
    private static let contractions: [String: String] = [
        "i'll":     "i will",
        "i'm":      "i am",
        "i've":     "i have",
        "i'd":      "i would",
        "you'll":   "you will",
        "you're":   "you are",
        "you've":   "you have",
        "you'd":    "you would",
        "he'll":    "he will",
        "he's":     "he is",
        "she'll":   "she will",
        "she's":    "she is",
        "it's":     "it is",
        "it'll":    "it will",
        "we'll":    "we will",
        "we're":    "we are",
        "we've":    "we have",
        "we'd":     "we would",
        "they'll":  "they will",
        "they're":  "they are",
        "they've":  "they have",
        "they'd":   "they would",
        "that's":   "that is",
        "that'll":  "that will",
        "that'd":   "that would",
        "there's":  "there is",
        "there'll": "there will",
        "here's":   "here is",
        "what's":   "what is",
        "what'll":  "what will",
        "who's":    "who is",
        "who'll":   "who will",
        "don't":    "do not",
        "doesn't":  "does not",
        "didn't":   "did not",
        "won't":    "will not",
        "wouldn't": "would not",
        "can't":    "cannot",
        "couldn't": "could not",
        "shouldn't":"should not",
        "isn't":    "is not",
        "aren't":   "are not",
        "wasn't":   "was not",
        "weren't":  "were not",
        "haven't":  "have not",
        "hasn't":   "has not",
        "hadn't":   "had not",
        "let's":    "let us",
        "would've": "would have",
        "could've": "could have",
        "should've": "should have",
        "might've": "might have",
        "must've":  "must have",
    ]

    // Hesitation fillers only. Do NOT strip words that often appear in real scripts
    // ("so", "well", "like", "actually", "right") — removing them collapses uniqueness
    // and makes common phrases collide across the document.
    static let fillerWords: Set<String> = [
        "um", "uh", "er", "ah", "uhm", "err"
    ]

    // MARK: - Main normalization entry point

    /// Normalize text for matching purposes.
    /// Returns lowercased, punctuation-stripped, contraction-expanded words.
    static func normalize(_ text: String) -> [String] {
        var lower = text.lowercased()

        // Replace curly apostrophes with straight
        lower = lower.replacingOccurrences(of: "\u{2019}", with: "'")
        lower = lower.replacingOccurrences(of: "\u{2018}", with: "'")
        lower = lower.replacingOccurrences(of: "\u{201C}", with: "")
        lower = lower.replacingOccurrences(of: "\u{201D}", with: "")

        // Expand contractions
        for (contraction, expansion) in contractions {
            lower = lower.replacingOccurrences(of: contraction,
                                               with: expansion,
                                               options: .caseInsensitive)
        }

        // Strip punctuation (keep hyphens as word separators)
        lower = lower.replacingOccurrences(of: "-", with: " ")
        let stripped = lower.unicodeScalars.filter { scalar in
            CharacterSet.letters.union(.whitespaces).contains(scalar)
        }
        let clean = String(stripped)

        // Tokenize
        let words = clean.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Remove fillers
        return words.filter { !fillerWords.contains($0) }
    }

    /// Normalize a single word
    static func normalizeWord(_ word: String) -> String {
        normalize(word).joined(separator: " ")
    }

    /// Strip leading/trailing punctuation from a display word to get the matching token
    static func stripPunctuation(_ word: String) -> String {
        var s = word.lowercased()
        s = s.replacingOccurrences(of: "\u{2019}", with: "'")
        let punctuation = CharacterSet.punctuationCharacters.union(.symbols)
        return s.unicodeScalars.filter { !punctuation.contains($0) }
            .map { String($0) }.joined()
    }
}
