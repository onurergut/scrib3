public struct SubtitleCue: Sendable, Hashable {
    public var text: String
    public let start: SubtitleTime
    public let end: SubtitleTime

    public init(start: SubtitleTime, end: SubtitleTime, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }

    public init(start: Double, end: Double, text: String) {
        self.init(
            start: SubtitleTime(seconds: start),
            end: SubtitleTime(seconds: end),
            text: text
        )
    }

    public var duration: Double {
        max(0, end.seconds - start.seconds)
    }
}
