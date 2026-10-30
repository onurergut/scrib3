import Foundation
import Testing
@testable import Scrib3Core

@Suite("SubtitleExporter")
struct SubtitleExporterTests {
    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("scrib3-export-\(UUID().uuidString)")
            .appendingPathComponent(name)
    }

    @Test func writesUTF8SRT() throws {
        let url = temporaryURL("clip.srt")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let cues = [SubtitleCue(start: 0, end: 1, text: "Hello")]

        try SubtitleExporter.write(cues: cues, format: .srt, to: url)

        let data = try Data(contentsOf: url)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text == SubtitleWriter.srt(cues))
        #expect(text.hasPrefix("1\n00:00:00,000"))
    }

    @Test func overwritesAnExistingFile() throws {
        let url = temporaryURL("clip.vtt")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "old".write(to: url, atomically: true, encoding: .utf8)
        let cues = [SubtitleCue(start: 0, end: 1, text: "New")]

        try SubtitleExporter.write(cues: cues, format: .vtt, to: url)

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text == SubtitleWriter.vtt(cues))
        #expect(!text.contains("old"))
    }

    @Test func writesAnEmptyFileForNoCues() throws {
        let url = temporaryURL("silent.txt")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try SubtitleExporter.write(cues: [], format: .txt, to: url)
        #expect(try Data(contentsOf: url).isEmpty)
    }
}
