import Foundation

// MARK: - FuzzyMatcher
// Provides token-level fuzzy matching for speech-to-script alignment.

struct FuzzyMatcher {

    /// High-frequency words that should not dominate alignment scores.
    private static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "to", "of", "in", "on", "at",
        "for", "is", "are", "was", "were", "be", "been", "am", "i", "you",
        "we", "they", "he", "she", "it", "this", "that", "with", "as", "by",
        "from", "my", "our", "your", "their"
    ]

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

    private static func tokenWeight(_ token: String) -> Double {
        stopwords.contains(token) ? 0.55 : 1.0
    }

    /// Accept threshold: slightly looser for longer content words (ASR often garbles them).
    private static func matchThreshold(for token: String) -> Double {
        token.count >= 7 ? 0.68 : 0.75
    }

    /// True when ASR/script disagree on compound spacing: "checkout" ↔ "check out".
    private static func compoundMatch(a: String, bParts: [String]) -> Double {
        guard bParts.count >= 2 else { return 0 }
        let joined = bParts.joined()
        let sim = similarity(a, joined)
        // Also accept if a starts with first part and ends with last (checkout / check+out)
        if sim >= 0.80 { return sim }
        if a.hasPrefix(bParts[0]) && a.hasSuffix(bParts[bParts.count - 1])
            && a.count >= joined.count - 1 && a.count <= joined.count + 1 {
            return 0.92
        }
        return sim >= 0.72 ? sim : 0
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

        var totalScore = 0.0
        var matched = 0
        var weightSum = 0.0

        var si = 0
        var ti = 0

        while si < scriptWindow.count && ti < transcriptSlice.count {
            let scriptToken = scriptWindow[si]
            let transcriptToken = transcriptSlice[ti]
            let sim = similarity(scriptToken, transcriptToken)
            let threshold = min(matchThreshold(for: scriptToken), matchThreshold(for: transcriptToken))

            if sim >= threshold {
                let weight = tokenWeight(scriptToken)
                totalScore += sim * weight
                weightSum += weight
                matched += 1
                si += 1
                ti += 1
                continue
            }

            // Compound: script "checkout" vs transcript "check" + "out"
            if ti + 1 < transcriptSlice.count {
                let compound = compoundMatch(a: scriptToken,
                                             bParts: [transcriptToken, transcriptSlice[ti + 1]])
                if compound >= 0.80 {
                    let weight = tokenWeight(scriptToken)
                    totalScore += compound * weight
                    weightSum += weight
                    matched += 1
                    si += 1
                    ti += 2
                    continue
                }
            }

            // Compound: script "check" + "out" vs transcript "checkout"
            if si + 1 < scriptWindow.count {
                let compound = compoundMatch(a: transcriptToken,
                                             bParts: [scriptToken, scriptWindow[si + 1]])
                if compound >= 0.80 {
                    let weight = max(tokenWeight(scriptToken), tokenWeight(scriptWindow[si + 1]))
                    totalScore += compound * weight
                    weightSum += weight
                    matched += 1
                    si += 2
                    ti += 1
                    continue
                }
            }

            // Try skipping one or more script tokens (hard/misheard word — catch up)
            var bestSkipScore = 0.0
            var bestSkip = 0
            let skipMax = min(4, scriptWindow.count - si - 1)
            if skipMax >= 1 {
                for skip in 1...skipMax {
                    let skipSim = similarity(scriptWindow[si + skip], transcriptSlice[ti])
                    let skipThreshold = matchThreshold(for: scriptWindow[si + skip])
                    if skipSim >= skipThreshold && skipSim > bestSkipScore {
                        bestSkipScore = skipSim
                        bestSkip = skip
                    }
                    // Also try compound after a skip
                    if ti + 1 < transcriptSlice.count {
                        let c = compoundMatch(a: scriptWindow[si + skip],
                                              bParts: [transcriptSlice[ti], transcriptSlice[ti + 1]])
                        if c > bestSkipScore {
                            bestSkipScore = c
                            bestSkip = skip
                        }
                    }
                }
            }
            if bestSkipScore >= 0.68 && bestSkip > 0 {
                si += bestSkip
                // Do not consume transcript yet — retry match at new script position
            } else {
                ti += 1 // skip the unmatched transcript token (filler/extra/ASR noise)
            }
        }

        guard matched > 0 else { return (0, si) }

        // Score = weighted avg similarity × coverage, with a light unique-phrase bonus
        let coverage = Double(matched) / Double(max(transcriptSlice.count, 1))
        let avgSim = totalScore / max(weightSum, 0.001)
        let jaccard = ngramJaccard(transcriptSlice, Array(scriptWindow.prefix(max(compareLen, 1))))
        let score = (avgSim * coverage) * (0.85 + 0.15 * jaccard)
        return (score, si)
    }

    // MARK: - Sliding window search

    struct AlignmentResult {
        let bestWordIndex: Int    // index into script tokens
        let confidence: Double    // 0..1
        let matchedTokenCount: Int
        /// How much the best score beats the second-best candidate (0 if unique/no runner-up).
        let scoreMargin: Double
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
        forwardPenaltyPerWord: Double = 0.08,
        minForwardFactor: Double = 0.25
    ) -> AlignmentResult {

        guard !transcriptTokens.isEmpty && !scriptTokens.isEmpty else {
            return AlignmentResult(bestWordIndex: currentIndex, confidence: 0,
                                   matchedTokenCount: 0, scoreMargin: 0)
        }

        let searchStart = max(0, currentIndex - searchRadius / 4) // limited backward search
        let searchEnd   = min(scriptTokens.count - 1, currentIndex + searchRadius)

        guard searchStart <= searchEnd else {
            return AlignmentResult(bestWordIndex: currentIndex, confidence: 0,
                                   matchedTokenCount: 0, scoreMargin: 0)
        }

        var bestIndex = currentIndex
        var bestScore = -1.0
        var secondBestScore = -1.0
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
                // Nearby contiguous matches are far more likely to be the words
                // actually being read. Floor is low so distant false positives lose.
                let distance = Double(si - currentIndex)
                let decay = 1.0 / (1.0 + forwardPenaltyPerWord * distance)
                score *= max(minForwardFactor, decay)
            }

            if score > bestScore {
                secondBestScore = bestScore
                bestScore = score
                bestIndex = si
                bestConsumed = consumed
            } else if score > secondBestScore {
                secondBestScore = score
            }
        }

        let margin: Double
        if secondBestScore < 0 {
            margin = bestScore
        } else {
            margin = max(0, bestScore - secondBestScore)
        }

        return AlignmentResult(
            bestWordIndex: bestIndex,
            confidence: max(0, min(1, bestScore)),
            matchedTokenCount: bestConsumed,
            scoreMargin: margin
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
