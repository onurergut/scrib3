import Foundation

public enum SubtitleExporter {
    public static func write(
        cues: [SubtitleCue],
        format: SubtitleFormat,
        to url: URL
    ) throws {
        let text = SubtitleWriter.render(cues, format: format)
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
