import Foundation

// MARK: - FuzzyMatcher
// Provides token-level fuzzy matching for speech-to-script alignment.

struct FuzzyMatcher {

    // MARK: - Levenshtein distance (character-level)

    static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aArr = Array(a)
        let bArr = Array(b)
        let n = aArr.count, m = bArr.count

        guard n > 0 else { return m }
        guard m > 0 else { return n }

        var row = Array(0...m)
        for i in 1...n {
            var prev = row[0]
            row[0] = i
            for j in 1...m {
                let temp = row[j]
                if aArr[i-1] == bArr[j-1] {
                    row[j] = prev
                } else {
                    row[j] = 1 + Swift.min(row[j], row[j-1], prev)
                }
                prev = temp
            }
        }
        return row[m]
    }

    /// Normalized similarity 0..1 (1 = identical)
    static func similarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1.0 }
        let dist = levenshteinDistance(a, b)
        let maxLen = max(a.count, b.count)
        return 1.0 - Double(dist) / Double(maxLen)
    }

    // MARK: - Token sequence matching

    /// Score how well `transcript` tokens match `script` tokens starting at a given offset.
    /// Returns a score in 0..1 and the number of script tokens consumed.
    static func scoreSequence(scriptTokens: [String],
                               transcriptTokens: [String],
                               scriptOffset: Int,
                               windowSize: Int = 20) -> (score: Double, scriptTokensConsumed: Int) {
        guard !transcriptTokens.isEmpty else { return (0, 0) }

        let available = min(windowSize, scriptTokens.count - scriptOffset)
        guard available > 0 else { return (0, 0) }

        let scriptWindow = Array(scriptTokens[scriptOffset..<(scriptOffset + available)])
        let compareLen = min(transcriptTokens.count, available)
        let transcriptSlice = Array(transcriptTokens.suffix(compareLen))

        // Dynamic programming: find best alignment
        var totalScore = 0.0
        var matched = 0

        var si = 0
        var ti = 0

        while si < scriptWindow.count && ti < transcriptSlice.count {
            let sim = similarity(scriptWindow[si], transcriptSlice[ti])
            if sim >= 0.75 {
                totalScore += sim
                matched += 1
                si += 1
                ti += 1
            } else {
                // Try skipping one script token (speaker omitted a word)
                var bestSkipScore = 0.0
                let skipMax = min(3, scriptWindow.count - si - 1)
                if skipMax >= 1 {
                    for skip in 1...skipMax {
                        let skipSim = similarity(scriptWindow[si + skip], transcriptSlice[ti])
                        if skipSim > bestSkipScore {
                            bestSkipScore = skipSim
                        }
                    }
                }
                if bestSkipScore >= 0.75 {
                    si += 1 // skip the unmatched script token
                } else {
                    ti += 1 // skip the unmatched transcript token (filler/extra)
                }
            }
        }

        guard matched > 0 else { return (0, si) }

        // Score = avg similarity of matched pairs, weighted by coverage
        let coverage = Double(matched) / Double(max(transcriptSlice.count, 1))
        return ((totalScore / Double(matched)) * coverage, si)
    }

    // MARK: - Sliding window search

    struct AlignmentResult {
        let bestWordIndex: Int    // index into script words
        let confidence: Double    // 0..1
        let matchedTokenCount: Int
    }

    /// Search for the best alignment of `transcriptTokens` within `scriptTokens`,
    /// searching around `currentIndex ± searchRadius`.
    /// Strongly prefers positions at or ahead of the current position.
    static func findBestAlignment(
        scriptTokens: [String],
        transcriptTokens: [String],
        currentIndex: Int,
        searchRadius: Int = 50,
        backtrackPenalty: Double = 0.3,
        forwardPenaltyPerWord: Double = 0.05
    ) -> AlignmentResult {

        guard !transcriptTokens.isEmpty && !scriptTokens.isEmpty else {
            return AlignmentResult(bestWordIndex: currentIndex, confidence: 0, matchedTokenCount: 0)
        }

        let searchStart = max(0, currentIndex - searchRadius / 4) // limited backward search
        let searchEnd   = min(scriptTokens.count - 1, currentIndex + searchRadius)

        guard searchStart <= searchEnd else {
            return AlignmentResult(bestWordIndex: currentIndex, confidence: 0, matchedTokenCount: 0)
        }

        var bestIndex = currentIndex
        var bestScore = -1.0
        var bestConsumed = 0

        for si in searchStart...searchEnd {
            let (rawScore, consumed) = scoreSequence(
                scriptTokens: scriptTokens,
                transcriptTokens: transcriptTokens,
                scriptOffset: si,
                windowSize: min(30, transcriptTokens.count + 5)
            )
            var score = rawScore

            // Apply backtrack penalty for positions before current
            if si < currentIndex {
                score *= (1.0 - backtrackPenalty)
            } else if si > currentIndex {
                // Penalize matches that are far ahead of the current position.
                // A match that leaps many words forward is usually a false positive
                // caused by repeated/common words (e.g. "it is", "I'll") re-appearing
                // later in the script. Nearby contiguous matches are far more likely
                // to be the words actually being read, so let them win unless a distant
                // match is dramatically stronger. The discount is capped so a genuinely
                // strong far match (speaker skipped ahead / a recognition gap) can still
                // be selected.
                let distance = Double(si - currentIndex)
                let decay = 1.0 / (1.0 + forwardPenaltyPerWord * distance)
                let minFactor = 0.5
                score *= max(minFactor, decay)
            }

            if score > bestScore {
                bestScore = score
                bestIndex = si
                bestConsumed = consumed
            }
        }

        return AlignmentResult(
            bestWordIndex: bestIndex,
            confidence: max(0, min(1, bestScore)),
            matchedTokenCount: bestConsumed
        )
    }

    // MARK: - N-gram Jaccard similarity (fast secondary check)

    static func ngramJaccard(_ a: [String], _ b: [String], n: Int = 2) -> Double {
        guard a.count >= n && b.count >= n else {
            // Fall back to unigram overlap
            let setA = Set(a)
            let setB = Set(b)
            let intersection = setA.intersection(setB).count
            let union = setA.union(setB).count
            return union > 0 ? Double(intersection) / Double(union) : 0
        }

        func ngrams(_ tokens: [String]) -> Set<String> {
            var result = Set<String>()
            for i in 0...(tokens.count - n) {
                result.insert(tokens[i..<(i+n)].joined(separator: " "))
            }
            return result
        }

        let ngramsA = ngrams(a)
        let ngramsB = ngrams(b)
        let intersection = ngramsA.intersection(ngramsB).count
        let union = ngramsA.union(ngramsB).count
        return union > 0 ? Double(intersection) / Double(union) : 0
    }
}
