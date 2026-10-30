import Foundation
import Scrib3Core
import Testing
@testable import Scrib3App

@Suite("App locale options")
struct AppLocaleOptionTests {
    @Test func usesAStableBCP47KeyForPickerSelection() {
        #expect(LocaleOption(locale: Locale(identifier: "tr_TR")).id == "tr-tr")
        #expect(LocaleOption(locale: Locale(identifier: "tr-TR")).id == "tr-tr")
        #expect(LocaleOption(locale: Locale(identifier: "en_US")).id == "en-us")
    }

    @Test func hasANonEmptyDisplayName() {
        let option = LocaleOption(locale: Locale(identifier: "tr_TR"))
        #expect(!option.displayName.isEmpty)
        #expect(option.displayName != option.id)
    }

    @Test func engineIdentifiersAreStableForPersistence() {
        #expect(EngineIdentifier.apple.rawValue == "apple")
        #expect(EngineIdentifier.whisperKit.rawValue == "whisperKit")
    }
}
