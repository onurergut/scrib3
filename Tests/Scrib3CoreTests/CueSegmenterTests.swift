import Testing
@testable import Scrib3Core

@Suite("CueSegmenter")
struct CueSegmenterTests {
    private func word(_ text: String, _ start: Double, _ end: Double) -> TimedWord {
        TimedWord(text: text, start: start, end: end)
    }

    private func rules(
        maxCharactersPerLine: Int = 42,
        maxLines: Int = 2,
        maxDuration: Double = 7,
        minDuration: Double = 0,
        pauseBoundary: Double = 0.6,
        minimumGap: Double = 0.05
    ) -> SegmentationRules {
        SegmentationRules(
            maxCharactersPerLine: maxCharactersPerLine,
            maxLines: maxLines,
            maxDuration: maxDuration,
            minDuration: minDuration,
            pauseBoundary: pauseBoundary,
            minimumGap: minimumGap
        )
    }

    @Test func groupsWordsIntoOneCue() {
        let cues = CueSegmenter(rules: rules()).segment([
            word("Hello", 0, 0.5),
            word("world", 0.5, 1.0),
        ])
        #expect(cues == [SubtitleCue(start: 0, end: 1.0, text: "Hello world")])
    }

    @Test func trimsAndCollapsesWordWhitespace() {
        let cues = CueSegmenter(rules: rules()).segment([
            word("  Hello ", 0, 0.5),
            word("\tworld  ", 0.5, 1.0),
        ])
        #expect(cues.map(\.text) == ["Hello world"])
    }

    @Test func splitsAfterSentencePunctuation() {
        let cues = CueSegmenter(rules: rules()).segment([
            word("Hello.", 0, 0.5),
            word("World", 0.7, 1.2),
        ])
        #expect(cues.map(\.text) == ["Hello.", "World"])
        #expect(cues[0].start.seconds == 0)
        #expect(cues[1].start.seconds == 0.7)
    }

    @Test func splitsOnQuestionAndExclamationMarks() {
        let cues = CueSegmenter(rules: rules()).segment([
            word("Really?", 0, 0.5),
            word("Yes!", 0.6, 1.0),
            word("Fine", 1.1, 1.5),
        ])
        #expect(cues.map(\.text) == ["Really?", "Yes!", "Fine"])
    }

    @Test func detectsSentenceEndAcrossQuotes() {
        let cues = CueSegmenter(rules: rules()).segment([
            word("\"Hello.\"", 0, 0.5),
            word("Next", 0.7, 1.2),
        ])
        #expect(cues.map(\.text) == ["\"Hello.\"", "Next"])
    }

    @Test func splitsOnPauseWithoutPunctuation() {
        let cues = CueSegmenter(rules: rules()).segment([
            word("merhaba", 0, 0.5),
            word("dünya", 1.3, 1.8),
        ])
        #expect(cues.map(\.text) == ["merhaba", "dünya"])
    }

    @Test func pauseExactlyAtThresholdSplits() {
        let cues = CueSegmenter(rules: rules(pauseBoundary: 0.5)).segment([
            word("one", 0, 0.5),
            word("two", 1.0, 1.5),
        ])
        #expect(cues.count == 2)
    }

    @Test func shortGapStaysInOneCue() {
        let cues = CueSegmenter(rules: rules()).segment([
            word("one", 0, 0.5),
            word("two", 0.7, 1.2),
        ])
        #expect(cues.count == 1)
    }

    @Test func splitsBeforeExceedingMaxDuration() {
        let words = (0..<10).map { word("w\($0)", Double($0), Double($0) + 0.5) }
        let cues = CueSegmenter(rules: rules(maxDuration: 7)).segment(words)
        #expect(cues.count == 2)
        #expect(cues[0].duration <= 7)
        #expect(cues[0].text == "w0 w1 w2 w3 w4 w5 w6")
        #expect(cues[1].text == "w7 w8 w9")
    }

    @Test func durationExactlyAtLimitStaysOneCue() {
        let cues = CueSegmenter(rules: rules(maxDuration: 7)).segment([
            word("start", 0, 6.5),
            word("end", 6.5, 7.0),
        ])
        #expect(cues.count == 1)
        #expect(cues[0].duration == 7)
    }

    @Test func longSingleWordMayExceedDuration() {
        let cues = CueSegmenter(rules: rules(maxDuration: 7)).segment([
            word("exceptionallylongword", 0, 9),
        ])
        #expect(cues.count == 1)
        #expect(cues[0].duration == 9)
    }

    @Test func enforcesCharacterBudgetAcrossTwoLines() {
        let words = (0..<10).map { word(String(repeating: "a", count: 10), Double($0), Double($0) + 0.5) }
        let cues = CueSegmenter(rules: rules()).segment(words)
        #expect(cues.count == 2)
        #expect(cues[0].text.split(separator: "\n").count <= 2)
        let unwrapped = cues[0].text.replacingOccurrences(of: "\n", with: " ")
        #expect(unwrapped.count <= 84)
    }

    @Test func breaksAtLargestGapWhenLimitsForceASplit() {
        var words: [TimedWord] = []
        var time = 0.0
        for index in 0..<10 {
            words.append(word("word\(index)" + String(repeating: "x", count: 8 - "word\(index)".count), time, time + 0.5))
            time += 0.5 + (index == 4 ? 0.4 : 0.1)
        }
        let cues = CueSegmenter(rules: rules()).segment(words)
        #expect(cues.count == 2)
        #expect(cues[0].text.split(whereSeparator: \.isWhitespace).count == 5)
        #expect(cues[1].text.split(whereSeparator: \.isWhitespace).count == 5)
    }

    @Test func wrapsTextIntoAtMostTwoLines() {
        let text = "the quick brown fox jumps over the lazy dog and keeps running"
        let cues = CueSegmenter(rules: rules()).segment([word(text, 0, 3)])
        #expect(cues.count == 1)
        #expect(cues[0].text.split(separator: "\n").count <= 2)
    }

    @Test func extendsShortFinalCueToMinimumDuration() {
        let cues = CueSegmenter(rules: rules(minDuration: 1.0)).segment([
            word("hi", 0, 0.2),
        ])
        #expect(cues[0].end.seconds == 1.0)
    }

    @Test func minimumDurationNeverOverlapsTheNextCue() {
        let cues = CueSegmenter(rules: rules(minDuration: 1.0, minimumGap: 0.05)).segment([
            word("hi.", 0, 0.2),
            word("there", 0.5, 1.0),
        ])
        #expect(cues[0].end.seconds == 0.45)
        #expect(cues[1].start.seconds == 0.5)
    }

    @Test func minimumDurationAppliesBeforeLargeSilence() {
        let cues = CueSegmenter(rules: rules(minDuration: 1.0)).segment([
            word("hi", 0, 0.2),
            word("later", 5.0, 5.5),
        ])
        #expect(cues[0].end.seconds == 1.0)
    }

    @Test func sortsOutOfOrderWords() {
        let cues = CueSegmenter(rules: rules()).segment([
            word("second", 1.0, 1.5),
            word("first", 0, 0.5),
        ])
        #expect(cues.map(\.text) == ["first second"])
    }

    @Test func ignoresBlankWords() {
        let cues = CueSegmenter(rules: rules()).segment([
            word("one", 0, 0.5),
            word("   ", 0.5, 0.6),
            word("two", 0.7, 1.2),
        ])
        #expect(cues.map(\.text) == ["one two"])
    }

    @Test func clampsNegativeTimes() {
        let cues = CueSegmenter(rules: rules(minDuration: 0)).segment([
            word("negative", -2, -1),
        ])
        #expect(cues[0].start.seconds == 0)
        #expect(cues[0].end.seconds == 0)
    }

    @Test func emptyInputProducesNoCues() {
        #expect(CueSegmenter(rules: rules()).segment([]).isEmpty)
        #expect(CueSegmenter(rules: rules()).segment([word("  ", 0, 1)]).isEmpty)
    }

    @Test func preservesEveryWordExactlyOnce() {
        let words = [
            word("Merhaba", 0, 0.4),
            word("dünya.", 0.4, 0.9),
            word("Bugün", 1.0, 1.4),
            word("hava", 1.4, 1.7),
            word("güzel", 1.7, 2.1),
        ]
        let cues = CueSegmenter(rules: rules()).segment(words)
        let reconstructed = cues
            .map { $0.text.replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: " ")
        #expect(reconstructed == words.map(\.text).joined(separator: " "))
    }

    @Test func isDeterministic() {
        let words = (0..<30).map { word("token\($0)", Double($0) * 0.7, Double($0) * 0.7 + 0.5) }
        let segmenter = CueSegmenter(rules: rules())
        #expect(segmenter.segment(words) == segmenter.segment(words))
    }

    @Test func maintainsInvariantsForGeneratedWordStreams() {
        var generator = LCG(seed: 0x5C1B3)
        let segmenter = CueSegmenter(rules: rules())

        for _ in 0..<200 {
            var words: [TimedWord] = []
            var time = 0.0
            let count = Int(generator.next(upperBound: 25)) + 1
            for _ in 0..<count {
                let length = Int(generator.next(upperBound: 12)) + 1
                let text = String((0..<length).map { _ in
                    Array("abcdefghijklmnopqrstuvwxyz")[Int(generator.next(upperBound: 26))]
                })
                let duration = 0.15 + Double(generator.next(upperBound: 250)) / 100
                let gap = Double(generator.next(upperBound: 100)) / 100
                words.append(word(text, time, time + duration))
                time += duration + gap
            }

            let cues = segmenter.segment(words)

            var previousStart = -Double.infinity
            var previousEnd = -Double.infinity
            for cue in cues {
                #expect(cue.start.seconds >= previousStart)
                #expect(cue.start.seconds >= previousEnd)
                #expect(cue.end.seconds >= cue.start.seconds)
                #expect(cue.text.split(separator: "\n").count <= 2)
                for line in cue.text.split(separator: "\n") {
                    let isSingleLongWord = !line.contains(" ")
                    if !isSingleLongWord {
                        #expect(line.count <= 42)
                    }
                }
                if cue.text.split(separator: " ").count > 1 {
                    #expect(cue.duration <= 7.0 + 0.0001)
                }
                previousStart = cue.start.seconds
                previousEnd = cue.end.seconds
            }

            let reconstructed = cues
                .map { $0.text.replacingOccurrences(of: "\n", with: " ") }
                .joined(separator: " ")
            let expected = words.map(\.text).joined(separator: " ")
            #expect(reconstructed == expected)
        }
    }
}

private struct LCG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(upperBound: UInt64) -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return (state >> 33) % upperBound
    }
}
