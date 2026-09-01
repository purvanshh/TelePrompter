import Foundation
import PDFKit

// MARK: - ScriptParser

final class ScriptParser {

    // MARK: - Public entry points

    static func parse(text: String) -> ScriptDocument {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }
        return buildDocument(from: text)
    }

    static func parseTXT(url: URL) throws -> String {
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func parseMarkdown(url: URL) throws -> String {
        let raw = try String(contentsOf: url, encoding: .utf8)
        return stripMarkdown(raw)
    }

    static func parsePDF(url: URL) throws -> String {
        guard let pdf = PDFDocument(url: url) else {
            throw ImportError.pdfUnreadable
        }
        var text = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i) {
                text += (page.string ?? "") + "\n\n"
            }
        }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { throw ImportError.pdfEmpty }
        return result
    }

    static func importFile(url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "txt":
            return try parseTXT(url: url)
        case "md", "markdown":
            return try parseMarkdown(url: url)
        case "pdf":
            return try parsePDF(url: url)
        default:
            // Attempt as plain text
            return try parseTXT(url: url)
        }
    }

    // MARK: - Error types

    enum ImportError: LocalizedError {
        case pdfUnreadable
        case pdfEmpty
        case unsupportedFormat(String)
        case readError(String)

        var errorDescription: String? {
            switch self {
            case .pdfUnreadable:       return "Could not open the PDF file."
            case .pdfEmpty:            return "No readable text was found in the PDF."
            case .unsupportedFormat(let ext): return "The file format .\(ext) is not supported."
            case .readError(let msg):  return "Could not read file: \(msg)"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .pdfUnreadable:  return "Make sure the PDF is not encrypted or corrupted."
            case .pdfEmpty:       return "The PDF may contain scanned images instead of text. Try exporting as TXT first."
            case .unsupportedFormat: return "Try saving the file as .txt or .md and importing again."
            case .readError:      return "Check that the file exists and you have permission to read it."
            }
        }
    }

    // MARK: - Markdown stripping

    private static func stripMarkdown(_ raw: String) -> String {
        var text = raw

        // Remove ATX headers
        text = text.replacingOccurrences(of: #"^#{1,6}\s+"#,
                                         with: "",
                                         options: .regularExpression)
        // Remove bold/italic markers
        text = text.replacingOccurrences(of: #"(\*\*|__)(.*?)\1"#, with: "$2", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(\*|_)(.*?)\1"#, with: "$2", options: .regularExpression)
        // Remove inline code
        text = text.replacingOccurrences(of: #"`[^`]*`"#, with: "", options: .regularExpression)
        // Remove links
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
        // Remove horizontal rules
        text = text.replacingOccurrences(of: #"^[-_*]{3,}$"#, with: "", options: .regularExpression)
        // Remove list markers
        text = text.replacingOccurrences(of: #"^[\*\-\+]\s+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)

        return text
    }

    // MARK: - Document building

    private static func buildDocument(from text: String) -> ScriptDocument {
        var words: [ScriptWord] = []
        var sentences: [ScriptSentence] = []
        var paragraphs: [ScriptParagraph] = []

        // Split into paragraphs (blank lines)
        let paragraphStrings = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var globalWordIdx = 0
        var globalSentenceIdx = 0
        var charCursor = 0

        for (paraIdx, paraText) in paragraphStrings.enumerated() {
            let paraCharOffset = charCursor

            let paraWordStart = globalWordIdx
            let paraSentenceStart = globalSentenceIdx

            // Split paragraph into sentences
            let sentenceStrings = splitSentences(paraText)

            for sentText in sentenceStrings {
                let sentCharOffset = charCursor
                let sentWordStart = globalWordIdx

                // Split sentence into words
                let wordTokens = sentText.components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }

                for token in wordTokens {
                    let normalized = TextNormalizer.normalizeWord(token)
                    if normalized.isEmpty {
                        charCursor += token.count + 1
                        continue
                    }
                    let word = ScriptWord(
                        id: globalWordIdx,
                        text: token,
                        normalized: normalized,
                        charOffset: charCursor,
                        sentenceIndex: globalSentenceIdx,
                        paragraphIndex: paraIdx
                    )
                    words.append(word)
                    globalWordIdx += 1
                    charCursor += token.count + 1
                }

                let sentence = ScriptSentence(
                    id: globalSentenceIdx,
                    text: sentText,
                    normalized: TextNormalizer.normalize(sentText).joined(separator: " "),
                    charOffset: sentCharOffset,
                    paragraphIndex: paraIdx,
                    wordRange: sentWordStart..<globalWordIdx
                )
                sentences.append(sentence)
                globalSentenceIdx += 1
                charCursor += 1 // sentence separator
            }

            let paragraph = ScriptParagraph(
                id: paraIdx,
                text: paraText,
                charOffset: paraCharOffset,
                sentenceRange: paraSentenceStart..<globalSentenceIdx,
                wordRange: paraWordStart..<globalWordIdx
            )
            paragraphs.append(paragraph)
            charCursor += 2 // paragraph separator
        }

        return ScriptDocument(
            original: text,
            words: words,
            sentences: sentences,
            paragraphs: paragraphs
        )
    }

    // MARK: - Sentence splitting

    private static func splitSentences(_ text: String) -> [String] {
        // Use NSLinguisticTagger for proper sentence boundary detection
        let tagger = NSLinguisticTagger(tagSchemes: [.tokenType], options: 0)
        tagger.string = text

        var sentences: [String] = []
        let range = NSRange(text.startIndex..., in: text)
        tagger.enumerateTags(in: range,
                              unit: .sentence,
                              scheme: .tokenType,
                              options: []) { _, tokenRange, _ in
            let sentence = (text as NSString).substring(with: tokenRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
        }

        // Fallback if tagger returned nothing
        if sentences.isEmpty {
            // Simple period/question/exclamation split
            let pattern = #"(?<=[.!?])\s+"#
            let parts = text.components(separatedBy: try! NSRegularExpression(pattern: pattern))
            return parts.filter { !$0.isEmpty }
        }

        return sentences
    }
}

// MARK: - NSRegularExpression splitting helper

private extension String {
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        let nsString = self as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: self, range: fullRange)

        var parts: [String] = []
        var lastEnd = 0

        for match in matches {
            let matchRange = match.range
            parts.append(nsString.substring(with: NSRange(location: lastEnd, length: matchRange.location - lastEnd)))
            lastEnd = matchRange.location + matchRange.length
        }
        parts.append(nsString.substring(from: lastEnd))
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
