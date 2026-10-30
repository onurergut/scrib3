import Testing
@testable import Scrib3Core

@Suite("Subtitle writers")
struct SubtitleWriterTests {
    private let sample = [
        SubtitleCue(start: 0, end: 1.5, text: "Hello"),
        SubtitleCue(start: 2, end: 3.25, text: "Line one\nLine two"),
    ]

    @Test func srtNumbersCuesFromOneAndSeparatesWithBlankLine() {
        #expect(SubtitleWriter.srt(sample) == """
        1
        00:00:00,000 --> 00:00:01,500
        Hello

        2
        00:00:02,000 --> 00:00:03,250
        Line one
        Line two

        """)
    }

    @Test func vttStartsWithHeaderAndUsesDotSeparator() {
        #expect(SubtitleWriter.vtt(sample) == """
        WEBVTT

        00:00:00.000 --> 00:00:01.500
        Hello

        00:00:02.000 --> 00:00:03.250
        Line one
        Line two

        """)
    }

    @Test func txtUnwrapsSoftLineBreaksAndSeparatesCues() {
        #expect(SubtitleWriter.txt(sample) == """
        Hello

        Line one Line two

        """)
    }

    @Test func emptyTranscriptProducesEmptySRTAndTXT() {
        #expect(SubtitleWriter.srt([]) == "")
        #expect(SubtitleWriter.txt([]) == "")
    }

    @Test func emptyTranscriptProducesOnlyVTTHeader() {
        #expect(SubtitleWriter.vtt([]) == "WEBVTT\n")
    }

    @Test func formatEnumMapsToExtensions() {
        #expect(SubtitleFormat.srt.fileExtension == "srt")
        #expect(SubtitleFormat.vtt.fileExtension == "vtt")
        #expect(SubtitleFormat.txt.fileExtension == "txt")
    }

    @Test func renderDispatchesByFormat() {
        #expect(SubtitleWriter.render(sample, format: .srt) == SubtitleWriter.srt(sample))
        #expect(SubtitleWriter.render(sample, format: .vtt) == SubtitleWriter.vtt(sample))
        #expect(SubtitleWriter.render(sample, format: .txt) == SubtitleWriter.txt(sample))
    }

    @Test func normalizesCRLFAndTrimsOuterBlankLines() {
        let cues = [SubtitleCue(start: 0, end: 1, text: "\nfirst\r\nsecond\n")]
        #expect(SubtitleWriter.srt(cues) == """
        1
        00:00:00,000 --> 00:00:01,000
        first
        second

        """)
    }

    @Test func preservesUnicodeTextExactly() {
        let cues = [SubtitleCue(start: 0, end: 1, text: "İstanbul'da ğüşiöç")]
        #expect(SubtitleWriter.vtt(cues) == """
        WEBVTT

        00:00:00.000 --> 00:00:01.000
        İstanbul'da ğüşiöç

        """)
    }

    @Test func cueWithEmptyTextStillWritesTimingBlock() {
        let cues = [SubtitleCue(start: 0, end: 1, text: "")]
        #expect(SubtitleWriter.srt(cues) == """
        1
        00:00:00,000 --> 00:00:01,000


        """)
    }
}
