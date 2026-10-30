import Foundation

/// One recognized word with its position on the media timeline, in seconds.
public struct TimedWord: Sendable, Hashable {
    public let text: String
    public let start: Double
    public let end: Double
    public let confidence: Double?

    public init(text: String, start: Double, end: Double, confidence: Double? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

/// Limits applied when turning words into subtitle cues.
public struct SegmentationRules: Sendable, Hashable {
    public var maxCharactersPerLine: Int
    public var maxLines: Int
    public var maxDuration: Double
    public var minDuration: Double
    public var pauseBoundary: Double
    public var minimumGap: Double

    public init(
        maxCharactersPerLine: Int = 42,
        maxLines: Int = 2,
        maxDuration: Double = 7,
        minDuration: Double = 0.8,
        pauseBoundary: Double = 0.6,
        minimumGap: Double = 0.05
    ) {
        self.maxCharactersPerLine = maxCharactersPerLine
        self.maxLines = maxLines
        self.maxDuration = maxDuration
        self.minDuration = minDuration
        self.pauseBoundary = pauseBoundary
        self.minimumGap = minimumGap
    }

    public static let standard = SegmentationRules()
}

/// Turns timed words into subtitle cues.
///
/// Words are grouped into sentences first: a sentence ends at punctuation or
/// at a pause of at least `pauseBoundary`. Sentences are never merged, so a
/// cue boundary never lands in the middle of a sentence unless the duration,
/// character, or line limits force it. Such a forced break prefers the
/// largest pause available inside the allowed window.
public struct CueSegmenter: Sendable {
    public let rules: SegmentationRules

    public init(rules: SegmentationRules = .standard) {
        self.rules = rules
    }

    public func segment(_ words: [TimedWord]) -> [SubtitleCue] {
        let cleaned = normalized(words)
        guard !cleaned.isEmpty else { return [] }

        var result: [SubtitleCue] = []
        for sentence in sentences(in: cleaned) {
            result.append(contentsOf: cues(for: sentence))
        }
        return applyingMinimumDuration(to: result)
    }

    // MARK: - Input

    private func normalized(_ words: [TimedWord]) -> [TimedWord] {
        words.compactMap { word in
            let text = word.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !text.isEmpty else { return nil }
            let start = max(0, word.start)
            let end = max(start, word.end)
            return TimedWord(text: text, start: start, end: end, confidence: word.confidence)
        }
        .sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
        }
    }

    private func sentences(in words: [TimedWord]) -> [[TimedWord]] {
        var sentences: [[TimedWord]] = []
        var current: [TimedWord] = []

        for (index, word) in words.enumerated() {
            current.append(word)
            let nextGap = index + 1 < words.count
                ? words[index + 1].start - word.end
                : .infinity
            if endsSentence(word.text) || nextGap >= rules.pauseBoundary {
                sentences.append(current)
                current = []
            }
        }

        if !current.isEmpty {
            sentences.append(current)
        }
        return sentences
    }

    // MARK: - Cue building

    private func cues(for sentence: [TimedWord]) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var index = 0

        while index < sentence.count {
            var end = index
            while end < sentence.count, fits(sentence[index...end]) {
                end += 1
            }

            if end == index {
                // A single word that breaks a limit still gets its own cue.
                end = index + 1
            } else if end < sentence.count, end - index > 1,
                      let breakAfter = largestPauseIndex(in: sentence, from: index, to: end) {
                end = breakAfter + 1
            }

            cues.append(makeCue(Array(sentence[index..<end])))
            index = end
        }

        return cues
    }

    private func makeCue(_ words: [TimedWord]) -> SubtitleCue {
        let text = words.map(\.text).joined(separator: " ")
        return SubtitleCue(
            start: SubtitleTime(seconds: words[0].start),
            end: SubtitleTime(seconds: words[words.count - 1].end),
            text: LineWrapper.wrap(
                text,
                maxCharactersPerLine: rules.maxCharactersPerLine,
                maxLines: rules.maxLines
            )
        )
    }

    private func fits(_ words: ArraySlice<TimedWord>) -> Bool {
        guard let first = words.first, let last = words.last else { return false }

        if words.count > 1, last.end - first.start > rules.maxDuration + 0.000_001 {
            return false
        }

        let text = words.map(\.text).joined(separator: " ")
        let wrapped = LineWrapper.wrap(
            text,
            maxCharactersPerLine: rules.maxCharactersPerLine,
            maxLines: rules.maxLines
        )
        let lines = wrapped.split(separator: "\n", omittingEmptySubsequences: false)

        guard lines.count <= rules.maxLines else { return false }
        for line in lines {
            if line.count <= rules.maxCharactersPerLine { continue }
            // A single unbreakable word may overflow its line.
            if !line.contains(" ") { continue }
            return false
        }
        return true
    }

    /// The largest inter-word pause inside `range`, if it stands out enough to
    /// be a better break than simply filling the cue to its limit.
    private func largestPauseIndex(
        in words: [TimedWord],
        from start: Int,
        to end: Int
    ) -> Int? {
        guard end - start > 1 else { return nil }

        var gaps: [(index: Int, gap: Double)] = []
        for index in start..<(end - 1) {
            let gap = words[index + 1].start - words[index].end
            if gap >= 0.15 {
                gaps.append((index, gap))
            }
        }
        guard let largest = gaps.max(by: { $0.gap < $1.gap }),
              largest.gap >= 0.25
        else { return nil }

        let secondLargest = gaps
            .filter { $0.index != largest.index }
            .map(\.gap)
            .max() ?? 0
        guard largest.gap >= secondLargest * 1.5 + 0.05 else { return nil }
        return largest.index
    }

    private func applyingMinimumDuration(to cues: [SubtitleCue]) -> [SubtitleCue] {
        guard rules.minDuration > 0 else { return cues }
        var adjusted = cues

        for index in adjusted.indices {
            let cue = adjusted[index]
            let target = cue.start.seconds + rules.minDuration
            guard cue.end.seconds < target else { continue }

            let limit = index + 1 < adjusted.count
                ? adjusted[index + 1].start.seconds - rules.minimumGap
                : .infinity
            let newEnd = min(target, limit)
            guard newEnd > cue.end.seconds else { continue }

            adjusted[index] = SubtitleCue(
                start: cue.start,
                end: SubtitleTime(seconds: newEnd),
                text: cue.text
            )
        }

        return adjusted
    }

    private func endsSentence(_ text: String) -> Bool {
        var candidate = Substring(text)
        let trailingClosers: Set<Character> = ["\"", "'", "”", "’", ")", "]", "}"]

        while let last = candidate.last, trailingClosers.contains(last) {
            candidate = candidate.dropLast()
        }
        guard let last = candidate.last else { return false }
        return ".!?…".contains(last)
    }
}
