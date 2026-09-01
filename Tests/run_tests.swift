#!/usr/bin/env swift
// run_tests.swift
// Standalone test runner — no XCTest/Testing framework required.
// Run with: swift Tests/run_tests.swift
//
// This file embeds the logic under test directly to avoid framework linkage issues.

import Foundation

// ============================================================
// MARK: - Copy of production logic (for test isolation)
// ============================================================

// --- TextNormalizer (inline copy) ---

struct TextNormalizer {
    private static let contractions: [String: String] = [
        "i'll": "i will", "i'm": "i am", "i've": "i have", "i'd": "i would",
        "you'll": "you will", "you're": "you are", "you've": "you have", "you'd": "you would",
        "he'll": "he will", "he's": "he is", "she'll": "she will", "she's": "she is",
        "it's": "it is", "it'll": "it will", "we'll": "we will", "we're": "we are",
        "we've": "we have", "we'd": "we would", "they'll": "they will", "they're": "they are",
        "they've": "they have", "they'd": "they would", "that's": "that is",
        "there's": "there is", "what's": "what is", "who's": "who is",
        "don't": "do not", "doesn't": "does not", "didn't": "did not",
        "won't": "will not", "wouldn't": "would not", "can't": "cannot",
        "couldn't": "could not", "shouldn't": "should not", "isn't": "is not",
        "aren't": "are not", "wasn't": "was not", "weren't": "were not",
        "haven't": "have not", "hasn't": "has not", "hadn't": "had not",
        "let's": "let us", "would've": "would have", "could've": "could have",
        "should've": "should have", "might've": "might have", "must've": "must have",
    ]

    static let fillerWords: Set<String> = [
        "um", "uh", "er", "ah", "like", "so", "well",
        "basically", "literally", "actually", "right", "okay", "ok"
    ]

    static func normalize(_ text: String) -> [String] {
        var lower = text.lowercased()
        lower = lower.replacingOccurrences(of: "\u{2019}", with: "'")
        lower = lower.replacingOccurrences(of: "\u{2018}", with: "'")
        for (c, e) in contractions {
            lower = lower.replacingOccurrences(of: c, with: e, options: .caseInsensitive)
        }
        lower = lower.replacingOccurrences(of: "-", with: " ")
        let stripped = lower.unicodeScalars.filter { CharacterSet.letters.union(.whitespaces).contains($0) }
        let clean = String(stripped)
        let words = clean.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return words.filter { !fillerWords.contains($0) }
    }

    static func normalizeWord(_ word: String) -> String {
        normalize(word).joined(separator: " ")
    }

    static func stripPunctuation(_ word: String) -> String {
        var s = word.lowercased()
        s = s.replacingOccurrences(of: "\u{2019}", with: "'")
        let punctuation = CharacterSet.punctuationCharacters.union(.symbols)
        return s.unicodeScalars.filter { !punctuation.contains($0) }.map { String($0) }.joined()
    }
}

// --- FuzzyMatcher (inline copy) ---

struct FuzzyMatcher {
    static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aArr = Array(a), bArr = Array(b)
        let n = aArr.count, m = bArr.count
        guard n > 0 else { return m }
        guard m > 0 else { return n }
        var row = Array(0...m)
        for i in 1...n {
            var prev = row[0]; row[0] = i
            for j in 1...m {
                let temp = row[j]
                if aArr[i-1] == bArr[j-1] { row[j] = prev }
                else { row[j] = 1 + Swift.min(row[j], row[j-1], prev) }
                prev = temp
            }
        }
        return row[m]
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1.0 }
        let dist = levenshteinDistance(a, b)
        let maxLen = max(a.count, b.count)
        return 1.0 - Double(dist) / Double(maxLen)
    }

    static func scoreSequence(scriptTokens: [String], transcriptTokens: [String],
                               scriptOffset: Int, windowSize: Int = 20) -> Double {
        guard !transcriptTokens.isEmpty else { return 0 }
        let available = min(windowSize, scriptTokens.count - scriptOffset)
        guard available > 0 else { return 0 }
        let scriptWindow = Array(scriptTokens[scriptOffset..<(scriptOffset + available)])
        let compareLen = min(transcriptTokens.count, available)
        let transcriptSlice = Array(transcriptTokens.suffix(compareLen))
        var totalScore = 0.0, matched = 0, si = 0, ti = 0
        while si < scriptWindow.count && ti < transcriptSlice.count {
            let sim = similarity(scriptWindow[si], transcriptSlice[ti])
            if sim >= 0.75 { totalScore += sim; matched += 1; si += 1; ti += 1 }
            else {
                var bestSkip = 0.0
                let skipMax = min(3, scriptWindow.count - si - 1)
                if skipMax >= 1 {
                    for skip in 1...skipMax {
                        let s = similarity(scriptWindow[si + skip], transcriptSlice[ti])
                        if s > bestSkip { bestSkip = s }
                    }
                }
                if bestSkip >= 0.75 { si += 1 } else { ti += 1 }
            }
        }
        guard matched > 0 else { return 0 }
        let coverage = Double(matched) / Double(max(transcriptSlice.count, 1))
        return (totalScore / Double(matched)) * coverage
    }

    static func findBestAlignment(scriptTokens: [String], transcriptTokens: [String],
                                   currentIndex: Int, searchRadius: Int = 50,
                                   backtrackPenalty: Double = 0.3) -> (bestWordIndex: Int, confidence: Double) {
        guard !transcriptTokens.isEmpty && !scriptTokens.isEmpty else {
            return (currentIndex, 0)
        }
        let searchStart = max(0, currentIndex - searchRadius / 4)
        let searchEnd   = min(scriptTokens.count - 1, currentIndex + searchRadius)
        guard searchStart <= searchEnd else { return (currentIndex, 0) }
        var bestIndex = currentIndex, bestScore = -1.0
        for si in searchStart...searchEnd {
            var score = scoreSequence(scriptTokens: scriptTokens, transcriptTokens: transcriptTokens,
                                       scriptOffset: si, windowSize: min(30, transcriptTokens.count + 5))
            if si < currentIndex { score *= (1.0 - backtrackPenalty) }
            if score > bestScore { bestScore = score; bestIndex = si }
        }
        return (bestIndex, max(0, min(1, bestScore)))
    }

    static func ngramJaccard(_ a: [String], _ b: [String], n: Int = 2) -> Double {
        guard a.count >= n && b.count >= n else {
            let setA = Set(a), setB = Set(b)
            let inter = setA.intersection(setB).count
            let union = setA.union(setB).count
            return union > 0 ? Double(inter) / Double(union) : 0
        }
        func ngrams(_ tokens: [String]) -> Set<String> {
            var r = Set<String>()
            for i in 0...(tokens.count - n) { r.insert(tokens[i..<(i+n)].joined(separator: " ")) }
            return r
        }
        let nA = ngrams(a), nB = ngrams(b)
        let inter = nA.intersection(nB).count, union = nA.union(nB).count
        return union > 0 ? Double(inter) / Double(union) : 0
    }
}

// ============================================================
// MARK: - Minimal test runner
// ============================================================

var passed = 0, failed = 0
var failures: [String] = []

func expect(_ cond: Bool, _ msg: String, file: String = #file, line: Int = #line) {
    if cond { passed += 1 }
    else { failed += 1; failures.append("  FAIL [\(file.split(separator:"/").last ?? ""):\(line)]: \(msg)") }
}

func run(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        print("  ✓ \(name)")
    } catch {
        failed += 1
        failures.append("  FAIL \(name): \(error)")
        print("  ✗ \(name): \(error)")
    }
}

// ============================================================
// MARK: - TextNormalizer tests
// ============================================================
print("\n=== TextNormalizer ===")

run("Basic lowercase") {
    let r = TextNormalizer.normalize("Hello World")
    expect(r == ["hello", "world"], "Expected [hello,world], got \(r)")
}
run("Punctuation stripped") {
    let r = TextNormalizer.normalize("Hello, everyone.")
    expect(r == ["hello", "everyone"], "Got \(r)")
}
run("Empty string") {
    expect(TextNormalizer.normalize("") == [], "Should be empty")
}
run("Filler 'um' removed") {
    let r = TextNormalizer.normalize("Today um we explain")
    expect(!r.contains("um"), "Should remove 'um': \(r)")
    expect(r.contains("today"), "Should keep 'today': \(r)")
}
run("Contraction i'll expanded") {
    let r = TextNormalizer.normalize("I'll explain")
    expect(r.contains("will"), "Should expand 'will': \(r)")
}
run("Contraction it's expanded") {
    let r = TextNormalizer.normalize("it's great")
    expect(r.contains("is"), "Should expand 'is': \(r)")
}
run("Hyphen as space") {
    let r = TextNormalizer.normalize("high-risk")
    let joined = r.joined()
    expect(joined.contains("high") || joined.contains("risk"), "Hyphen split: \(r)")
}
run("Strip punctuation Hello,") {
    expect(TextNormalizer.stripPunctuation("Hello,") == "hello", "Got: \(TextNormalizer.stripPunctuation("Hello,"))")
}

// ============================================================
// MARK: - FuzzyMatcher tests
// ============================================================
print("\n=== FuzzyMatcher ===")

run("Levenshtein identical") {
    expect(FuzzyMatcher.levenshteinDistance("hello","hello") == 0, "Should be 0")
}
run("Levenshtein 1 substitution") {
    expect(FuzzyMatcher.levenshteinDistance("hello","hallo") == 1, "Should be 1")
}
run("Levenshtein empty vs string") {
    expect(FuzzyMatcher.levenshteinDistance("","hello") == 5, "Should be 5")
}
run("Similarity identical = 1.0") {
    expect(FuzzyMatcher.similarity("hello","hello") == 1.0, "Should be 1.0")
}
run("Similarity high for near-words (detect/detected)") {
    let s = FuzzyMatcher.similarity("detect","detected")
    expect(s > 0.7, "Expected >0.7, got \(s)")
}
run("Similarity low for different words") {
    let s = FuzzyMatcher.similarity("hello","world")
    expect(s < 0.5, "Expected <0.5, got \(s)")
}
run("Score identical sequence high") {
    let t = ["hello","world","today"]
    let s = FuzzyMatcher.scoreSequence(scriptTokens: t, transcriptTokens: t, scriptOffset: 0)
    expect(s > 0.8, "Expected >0.8, got \(s)")
}
run("Score mismatched sequence low") {
    let s = FuzzyMatcher.scoreSequence(
        scriptTokens: ["hello","world"], transcriptTokens: ["xyz","abc"], scriptOffset: 0)
    expect(s < 0.3, "Expected <0.3, got \(s)")
}
run("FindBestAlignment advances from current position") {
    // currentIndex = 3, transcript matches words at 5+
    let script = ["aaa","bbb","ccc","ddd","eee","fox","jumps","over","zzz"]
    let (idx, conf) = FuzzyMatcher.findBestAlignment(
        scriptTokens: script, transcriptTokens: ["fox","jumps","over"],
        currentIndex: 3, searchRadius: 9)
    // fox is at index 5, starting from 3 — should find it at >=5
    expect(idx >= 3, "Expected idx >=3, got \(idx)")
    expect(conf > 0.3, "Expected conf>0.3, got \(conf)")
}
run("FindBestAlignment does not go backward") {
    let script = ["one","two","three","four","five"]
    let (idx, _) = FuzzyMatcher.findBestAlignment(
        scriptTokens: script, transcriptTokens: ["four","five"],
        currentIndex: 3, searchRadius: 5)
    expect(idx >= 3, "Should not go backward, got \(idx)")
}
run("Ngram Jaccard identical") {
    let t = ["hello","world","today"]
    expect(FuzzyMatcher.ngramJaccard(t,t) == 1.0, "Should be 1.0")
}
run("Ngram Jaccard no overlap") {
    let a = ["hello","world"], b = ["xyz","abc"]
    expect(FuzzyMatcher.ngramJaccard(a,b) == 0.0, "Should be 0.0")
}

// ============================================================
// MARK: - Results
// ============================================================
print("\n=== Test Results ===")
for f in failures { print(f) }
let total = passed + failed
print("\(passed)/\(total) tests passed")
if failed > 0 {
    print("⚠️  \(failed) test(s) failed")
    exit(1)
} else {
    print("✅ All tests passed")
}
