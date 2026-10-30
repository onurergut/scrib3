import Foundation

/// A non-negative point in a media timeline, stored as whole milliseconds.
///
/// Subtitle formats express time as `HH:MM:SS,mmm` (SRT) or `HH:MM:SS.mmm`
/// (WebVTT). Storing milliseconds keeps formatting exact and avoids the
/// rounding drift that repeated `Double` arithmetic would introduce.
public struct SubtitleTime: Sendable, Hashable, Comparable {
    public let milliseconds: Int

    public init(milliseconds: Int) {
        self.milliseconds = max(0, milliseconds)
    }

    public init(seconds: Double) {
        guard seconds.isFinite, seconds > 0 else {
            self.init(milliseconds: 0)
            return
        }
        self.init(milliseconds: Int((seconds * 1000).rounded()))
    }

    public var seconds: Double {
        Double(milliseconds) / 1000
    }

    public var srtTimestamp: String {
        formatted(separator: ",")
    }

    public var vttTimestamp: String {
        formatted(separator: ".")
    }

    public static func < (lhs: SubtitleTime, rhs: SubtitleTime) -> Bool {
        lhs.milliseconds < rhs.milliseconds
    }

    private func formatted(separator: Character) -> String {
        let totalSeconds = milliseconds / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let millis = milliseconds % 1000
        let hoursField = String(format: "%02d", hours)
        let minutesField = String(format: "%02d", minutes)
        let secondsField = String(format: "%02d", seconds)
        let millisField = String(format: "%03d", millis)
        return "\(hoursField):\(minutesField):\(secondsField)\(separator)\(millisField)"
    }
}
