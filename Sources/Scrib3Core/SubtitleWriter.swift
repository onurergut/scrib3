import Foundation

public enum SubtitleFormat: String, CaseIterable, Sendable, Identifiable {
    case srt
    case vtt
    case txt

    public var id: String { rawValue }

    public var fileExtension: String { rawValue }
}

public enum SubtitleWriter {
    public static func render(_ cues: [SubtitleCue], format: SubtitleFormat) -> String {
        switch format {
        case .srt: srt(cues)
        case .vtt: vtt(cues)
        case .txt: txt(cues)
        }
    }

    public static func srt(_ cues: [SubtitleCue]) -> String {
        let blocks = cues.enumerated().map { index, cue in
            "\(index + 1)\n\(cue.start.srtTimestamp) --> \(cue.end.srtTimestamp)\n\(normalizedText(cue.text))"
        }
        return terminated(blocks)
    }

    public static func vtt(_ cues: [SubtitleCue]) -> String {
        let blocks = cues.map { cue in
            "\(cue.start.vttTimestamp) --> \(cue.end.vttTimestamp)\n\(normalizedText(cue.text))"
        }
        return "WEBVTT\n" + (blocks.isEmpty ? "" : "\n" + blocks.joined(separator: "\n\n") + "\n")
    }

    public static func txt(_ cues: [SubtitleCue]) -> String {
        let blocks = cues.map { cue in
            normalizedText(cue.text)
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
        }
        return terminated(blocks)
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func terminated(_ blocks: [String]) -> String {
        blocks.isEmpty ? "" : blocks.joined(separator: "\n\n") + "\n"
    }
}
