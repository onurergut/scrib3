import Foundation
import Testing
@testable import Scrib3Core

@Suite("OutputNaming")
struct OutputNamingTests {
    @Test func stripsTheMediaExtension() {
        #expect(OutputNaming.baseName(for: URL(fileURLWithPath: "/tmp/clip.m4a")) == "clip")
        #expect(OutputNaming.baseName(for: URL(fileURLWithPath: "/tmp/clip.final.mp4")) == "clip.final")
    }

    @Test func keepsNamesWithoutAnExtension() {
        #expect(OutputNaming.baseName(for: URL(fileURLWithPath: "/tmp/clip")) == "clip")
    }

    @Test func writesNextToTheSourceByDefault() {
        let url = OutputNaming.outputURL(
            source: URL(fileURLWithPath: "/Users/me/Movies/clip.mov"),
            format: .srt
        )
        #expect(url.path == "/Users/me/Movies/clip.srt")
    }

    @Test func honorsAnExplicitDirectory() {
        let url = OutputNaming.outputURL(
            source: URL(fileURLWithPath: "/Users/me/Movies/clip.mov"),
            format: .vtt,
            directory: URL(fileURLWithPath: "/Users/me/Subtitles", isDirectory: true)
        )
        #expect(url.path == "/Users/me/Subtitles/clip.vtt")
    }

    @Test func preservesUnicodeAndSpaces() {
        let url = OutputNaming.outputURL(
            source: URL(fileURLWithPath: "/tmp/İstanbul gezisi.m4a"),
            format: .txt
        )
        #expect(url.lastPathComponent == "İstanbul gezisi.txt")
    }

    @Test func handlesUppercaseExtensions() {
        let url = OutputNaming.outputURL(
            source: URL(fileURLWithPath: "/tmp/CLIP.MP4"),
            format: .srt
        )
        #expect(url.lastPathComponent == "CLIP.srt")
    }
}
