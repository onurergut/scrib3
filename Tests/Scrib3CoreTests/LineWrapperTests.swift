import Testing
@testable import Scrib3Core

@Suite("LineWrapper")
struct LineWrapperTests {
    @Test func leavesShortTextOnOneLine() {
        #expect(LineWrapper.wrap("Hello there") == "Hello there")
    }

    @Test func leavesTextExactlyAtTheLimitAlone() {
        let text = String(repeating: "a", count: 42)
        #expect(LineWrapper.wrap(text) == text)
    }

    @Test func breaksLongTextIntoTwoBalancedLines() {
        let text = "the quick brown fox jumps over the lazy dog"
        #expect(LineWrapper.wrap(text) == """
        the quick brown fox
        jumps over the lazy dog
        """)
    }

    @Test func respectsThePerLineLimit() {
        let text = "one two three four five six seven eight nine ten eleven"
        let wrapped = LineWrapper.wrap(text)
        for component in wrapped.split(separator: "\n") {
            #expect(component.count <= 42)
        }
    }

    @Test func keepsLongSingleWordIntact() {
        let word = String(repeating: "x", count: 60)
        #expect(LineWrapper.wrap(word) == word)
    }

    @Test func collapsesWhitespaceBeforeWrapping() {
        #expect(LineWrapper.wrap("  hello    world  ") == "hello world")
        #expect(LineWrapper.wrap("hello\nworld") == "hello world")
    }

    @Test func preservesTurkishCharacters() {
        let text = "İstanbul'da yaşayan çocuklar ğüşiöç harflerini öğreniyor"
        let wrapped = LineWrapper.wrap(text)
        #expect(wrapped.contains("\n"))
        #expect(wrapped.replacingOccurrences(of: "\n", with: " ") == text)
    }

    @Test func prefersPunctuationWhenTheSplitIsBalanced() {
        let text = "One two three four five. Six seven eight nine ten"
        #expect(LineWrapper.wrap(text) == """
        One two three four five.
        Six seven eight nine ten
        """)
    }

    @Test func emptyTextStaysEmpty() {
        #expect(LineWrapper.wrap("") == "")
        #expect(LineWrapper.wrap("   ") == "")
    }

    @Test func singleLineModeDoesNotBreak() {
        let text = "the quick brown fox jumps over the lazy dog"
        #expect(LineWrapper.wrap(text, maxLines: 1) == text)
    }

    @Test func overflowTextGoesOnTheSecondLine() {
        let text = String(repeating: "word ", count: 20).trimmingCharacters(in: .whitespaces)
        let lines = LineWrapper.wrap(text).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].count <= 42)
    }
}
