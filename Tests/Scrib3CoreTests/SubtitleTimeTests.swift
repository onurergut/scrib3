import Testing
@testable import Scrib3Core

@Suite("SubtitleTime")
struct SubtitleTimeTests {
    @Test func formatsZeroForSRTAndVTT() {
        let time = SubtitleTime(milliseconds: 0)
        #expect(time.srtTimestamp == "00:00:00,000")
        #expect(time.vttTimestamp == "00:00:00.000")
    }

    @Test func formatsSubSecondMilliseconds() {
        #expect(SubtitleTime(milliseconds: 7).srtTimestamp == "00:00:00,007")
        #expect(SubtitleTime(milliseconds: 90).srtTimestamp == "00:00:00,090")
        #expect(SubtitleTime(milliseconds: 999).srtTimestamp == "00:00:00,999")
    }

    @Test func formatsSecondsMinutesAndHours() {
        #expect(SubtitleTime(milliseconds: 1_234).srtTimestamp == "00:00:01,234")
        #expect(SubtitleTime(milliseconds: 61_000).srtTimestamp == "00:01:01,000")
        #expect(SubtitleTime(milliseconds: 3_723_456).srtTimestamp == "01:02:03,456")
    }

    @Test func rollsOverAtEachBoundary() {
        #expect(SubtitleTime(milliseconds: 59_999).srtTimestamp == "00:00:59,999")
        #expect(SubtitleTime(milliseconds: 60_000).srtTimestamp == "00:01:00,000")
        #expect(SubtitleTime(milliseconds: 3_599_999).srtTimestamp == "00:59:59,999")
        #expect(SubtitleTime(milliseconds: 3_600_000).srtTimestamp == "01:00:00,000")
    }

    @Test func keepsHoursUnpaddedBeyondTwoDigits() {
        #expect(SubtitleTime(milliseconds: 360_000_000).srtTimestamp == "100:00:00,000")
    }

    @Test func usesMillisecondSeparatorPerFormat() {
        let time = SubtitleTime(milliseconds: 3_723_456)
        #expect(time.srtTimestamp.contains(","))
        #expect(time.vttTimestamp == "01:02:03.456")
        #expect(time.vttTimestamp.contains("."))
    }

    @Test func clampsNegativeValuesToZero() {
        #expect(SubtitleTime(milliseconds: -5).milliseconds == 0)
        #expect(SubtitleTime(seconds: -1.5).milliseconds == 0)
        #expect(SubtitleTime(seconds: -0.0001).srtTimestamp == "00:00:00,000")
    }

    @Test func roundsSecondsToNearestMillisecond() {
        #expect(SubtitleTime(seconds: 1.2344).milliseconds == 1_234)
        #expect(SubtitleTime(seconds: 1.2346).milliseconds == 1_235)
        #expect(SubtitleTime(seconds: 0.0009).milliseconds == 1)
    }

    @Test func reportsExactSeconds() {
        #expect(SubtitleTime(milliseconds: 1_500).seconds == 1.5)
    }

    @Test func comparesChronologically() {
        #expect(SubtitleTime(milliseconds: 1) < SubtitleTime(milliseconds: 2))
        #expect(SubtitleTime(milliseconds: 2) >= SubtitleTime(milliseconds: 2))
        #expect(SubtitleTime(milliseconds: 3) > SubtitleTime(milliseconds: 2))
    }
}
