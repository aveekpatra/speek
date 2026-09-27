//
//  SpeekTests.swift
//  SpeekTests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import Testing
import Foundation
@testable import Speek

struct SpeekTests {

    /// A concrete default here pins every recording to one language and makes the
    /// Languages chips in Settings do nothing, which is how Czech kept getting
    /// transcribed as English.
    @Test func selectedLanguageDefaultsToAuto() async throws {
        AppDefaults.registerDefaults()
        #expect(UserDefaults.standard.string(forKey: "SelectedLanguage") == "auto")
    }

    @Test func dashboardHeroVariantsAreNumberedWithoutGaps() async throws {
        let rawValues = DashboardHeroVariant.allCases.map(\.rawValue)
        #expect(rawValues == Array(1...rawValues.count))
        #expect(DashboardHeroVariant.allCases.map(\.label) == rawValues.map { "V\($0)" })
    }

    @Test func dashboardHeroVariantFallsBackToOverviewForInvalidStoredValue() async throws {
        #expect(DashboardHeroVariant(storedValue: 0) == .overview)
        #expect(DashboardHeroVariant(storedValue: 99) == .overview)
    }

    @MainActor
    @Test func englishCoachParsesSuggestionResponse() async throws {
        let parsed = EnglishCoachService.parse("""
        SUGGESTION: YES
        SAID: "borrow me your phone"
        CORRECTED: "lend me your phone"
        WHY: Use lend when someone gives something to you.
        """)

        #expect(parsed?.said == "borrow me your phone")
        #expect(parsed?.corrected == "lend me your phone")
        #expect(parsed?.why == "Use lend when someone gives something to you.")
    }

    @MainActor
    @Test func englishCoachIgnoresNoSuggestionResponse() async throws {
        let parsed = EnglishCoachService.parse("""
        SUGGESTION: NO
        SAID:
        CORRECTED:
        WHY:
        """)

        #expect(parsed == nil)
    }

}
