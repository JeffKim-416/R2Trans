import Foundation

/// The text state needed to render the live interpreter transcript.
///
/// History is intentionally kept separate from the focused, recent text. The
/// latter can be shown prominently while the former remains available for
/// review. The values are immutable so a UI update always represents one
/// consistent point in time.
struct LiveInterpreterTranscriptSnapshot: Equatable, Sendable {
    let sourceHistory: String
    let officialHistory: String
    let latestSource: String
    let latestOfficial: String
    let provisional: String
    let historyTruncated: Bool

    init(
        sourceHistory: String = "",
        officialHistory: String = "",
        latestSource: String = "",
        latestOfficial: String = "",
        provisional: String = "",
        historyTruncated: Bool = false
    ) {
        self.sourceHistory = sourceHistory
        self.officialHistory = officialHistory
        self.latestSource = latestSource
        self.latestOfficial = latestOfficial
        self.provisional = provisional
        self.historyTruncated = historyTruncated
    }
}

/// Main-actor-owned text accumulator used by the realtime interpreter.
///
/// This type deliberately does not attempt to pair source and translated
/// utterances. The realtime events do not carry a stable shared utterance ID,
/// so pairing them by arrival order would be misleading.
struct LiveInterpreterTranscriptAccumulator: Sendable {
    static let sourceHistoryLimit = 50_000
    static let officialHistoryLimit = 50_000
    static let provisionalLimit = 320
    static let sourceFocusLimit = 240
    static let officialFocusLimit = 320
    static let focusSentenceLimit = 3

    private(set) var sourceHistory = ""
    private(set) var officialHistory = ""
    private(set) var provisional = ""
    private(set) var historyTruncated = false

    /// Source received since the most recent official translation. It is
    /// bounded independently because it is also used as the provisional
    /// translation request window.
    private(set) var sourceSinceOfficialOutput = ""

    var snapshot: LiveInterpreterTranscriptSnapshot {
        let latestSource = Self.recentTail(
            from: sourceSinceOfficialOutput.isEmpty ? sourceHistory : sourceSinceOfficialOutput,
            maxCharacters: Self.sourceFocusLimit,
            maxSentences: Self.focusSentenceLimit
        )
        let latestOfficial = Self.recentTail(
            from: officialHistory,
            maxCharacters: Self.officialFocusLimit,
            maxSentences: Self.focusSentenceLimit
        )
        return LiveInterpreterTranscriptSnapshot(
            sourceHistory: sourceHistory,
            officialHistory: officialHistory,
            latestSource: latestSource,
            latestOfficial: latestOfficial,
            provisional: Self.recentTail(
                from: provisional,
                maxCharacters: Self.provisionalLimit,
                maxSentences: Self.focusSentenceLimit
            ),
            historyTruncated: historyTruncated
        )
    }

    mutating func appendSource(_ delta: String) {
        guard !delta.isEmpty else {
            return
        }

        sourceHistory = Self.appendBounded(
            sourceHistory,
            delta: delta,
            limit: Self.sourceHistoryLimit,
            didTruncate: &historyTruncated
        )
        sourceSinceOfficialOutput = Self.trimmedTail(
            sourceSinceOfficialOutput + delta,
            limit: 2_000
        )
    }

    mutating func appendOfficial(_ delta: String) {
        guard !delta.isEmpty else {
            return
        }

        officialHistory = Self.appendBounded(
            officialHistory,
            delta: delta,
            limit: Self.officialHistoryLimit,
            didTruncate: &historyTruncated
        )
        provisional = ""
        sourceSinceOfficialOutput = ""
    }

    mutating func setProvisional(_ text: String) {
        provisional = Self.trimmedTail(text, limit: Self.provisionalLimit)
    }

    mutating func clearProvisional() {
        provisional = ""
    }

    mutating func reset() {
        sourceHistory = ""
        officialHistory = ""
        provisional = ""
        sourceSinceOfficialOutput = ""
        historyTruncated = false
    }

    private static func appendBounded(
        _ existing: String,
        delta: String,
        limit: Int,
        didTruncate: inout Bool
    ) -> String {
        let combined = existing + delta
        guard combined.count > limit else {
            return combined
        }

        didTruncate = true
        return trimmedTail(combined, limit: limit)
    }

    private static func trimmedTail(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        return String(value.suffix(limit))
    }

    /// Returns the most recent few sentences without changing their
    /// punctuation. A decimal/version dot is not treated as a sentence end.
    private static func recentTail(
        from value: String,
        maxCharacters: Int,
        maxSentences: Int
    ) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return ""
        }

        let sentenceEnds = sentenceBoundaryEnds(in: text)
        var start = text.startIndex

        if sentenceEnds.count > maxSentences {
            start = sentenceEnds[sentenceEnds.count - maxSentences - 1]
        }

        var result = String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.count > maxCharacters else {
            return result
        }

        let suffixStart = text.index(text.endIndex, offsetBy: -maxCharacters)
        // Prefer a complete sentence boundary after the hard character limit.
        // If the newest sentence itself is too long, retaining its tail is
        // preferable to dropping the live text altogether.
        if let boundary = sentenceEnds.first(where: { $0 >= suffixStart && $0 < text.endIndex }) {
            result = String(text[boundary...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            result = String(text[suffixStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if result.count > maxCharacters {
            result = String(result.suffix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func sentenceBoundaryEnds(in text: String) -> [String.Index] {
        var ends: [String.Index] = []

        for index in text.indices {
            let character = text[index]
            guard ".!?。！？".contains(character) else {
                continue
            }

            let nextIndex = text.index(after: index)
            if character == "." {
                let previous = index > text.startIndex ? text[text.index(before: index)] : nil
                let next = nextIndex < text.endIndex ? text[nextIndex] : nil
                // Keep decimal numbers and versions such as 3.14 and 1.0.0
                // intact. English sentence punctuation is otherwise accepted
                // only before whitespace or the end of the text.
                if previous?.isNumber == true, next?.isNumber == true {
                    continue
                }
                if let next, !next.isWhitespace {
                    continue
                }
            } else if nextIndex < text.endIndex, ".!?。！？".contains(text[nextIndex]) {
                continue
            }

            ends.append(nextIndex)
        }

        return ends
    }
}
