import Foundation

/// Wraps a single line of subtitle text into at most `maxLines` balanced lines.
///
/// Words are never split. If one word is longer than the line limit it keeps
/// its own line and overflows; callers that need a hard limit must split the
/// text before calling.
public enum LineWrapper {
    public static func wrap(
        _ text: String,
        maxCharactersPerLine: Int = 42,
        maxLines: Int = 2
    ) -> String {
        let cleaned = normalized(text)
        guard !cleaned.isEmpty else { return "" }
        guard maxCharactersPerLine > 0, maxLines > 1 else { return cleaned }
        guard cleaned.count > maxCharactersPerLine else { return cleaned }

        let tokens = cleaned.split(separator: " ").map(String.init)
        guard tokens.count > 1 else { return cleaned }

        if let split = bestSplit(tokens, maxCharactersPerLine: maxCharactersPerLine) {
            let first = tokens[..<split].joined(separator: " ")
            let second = tokens[split...].joined(separator: " ")
            return first + "\n" + second
        }

        return greedyOverflow(tokens, maxCharactersPerLine: maxCharactersPerLine)
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func bestSplit(
        _ tokens: [String],
        maxCharactersPerLine: Int
    ) -> Int? {
        var best: (index: Int, difference: Int, endsSentence: Bool)?

        for index in 1..<tokens.count {
            let first = tokens[..<index].joined(separator: " ")
            let second = tokens[index...].joined(separator: " ")
            guard first.count <= maxCharactersPerLine,
                  second.count <= maxCharactersPerLine
            else { continue }

            let difference = abs(first.count - second.count)
            let endsSentence = endsSentence(tokens[index - 1])

            if let current = best {
                let better = difference < current.difference
                    || (difference == current.difference && endsSentence && !current.endsSentence)
                if better {
                    best = (index, difference, endsSentence)
                }
            } else {
                best = (index, difference, endsSentence)
            }
        }

        return best?.index
    }

    private static func greedyOverflow(
        _ tokens: [String],
        maxCharactersPerLine: Int
    ) -> String {
        var firstLine: [String] = []
        var index = 0

        while index < tokens.count {
            let candidate = firstLine + [tokens[index]]
            guard candidate.joined(separator: " ").count <= maxCharactersPerLine else { break }
            firstLine = candidate
            index += 1
        }

        guard !firstLine.isEmpty, index < tokens.count else {
            return tokens.joined(separator: " ")
        }

        let secondLine = tokens[index...].joined(separator: " ")
        return firstLine.joined(separator: " ") + "\n" + secondLine
    }

    private static func endsSentence(_ token: String) -> Bool {
        guard let last = token.last else { return false }
        return ".!?…".contains(last)
    }
}
