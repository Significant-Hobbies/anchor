import Foundation
import Testing

@testable import AnchorCore

@Suite("Shared appearance preferences")
struct AnchorPreferencesTests {
    @Test("No record uses Anchor's shared dark default")
    func missingPreferenceUsesDark() {
        #expect(AnchorPreferencesPolicy.appearance(in: []) == .dark)
    }

    @Test("Unknown stored values degrade to the product default")
    func unknownValueUsesDark() {
        let preference = AnchorPreferences(appearance: .dark)
        preference.appearanceRaw = "future-value"

        #expect(preference.appearance == .dark)
    }

    @Test("The newest device update wins")
    func newestUpdateWins() {
        let older = AnchorPreferences(
            appearance: .light,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = AnchorPreferences(
            appearance: .dark,
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        #expect(AnchorPreferencesPolicy.appearance(in: [newer, older]) == .dark)
        #expect(AnchorPreferencesPolicy.latest(in: [older, newer]) === newer)
    }

    @Test("Equal timestamps resolve deterministically")
    func equalTimestampUsesStableIdentifierOrder() {
        let timestamp = Date(timeIntervalSince1970: 3_000)
        let lower = AnchorPreferences(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            appearance: .light,
            updatedAt: timestamp
        )
        let higher = AnchorPreferences(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            appearance: .dark,
            updatedAt: timestamp
        )

        #expect(AnchorPreferencesPolicy.latest(in: [higher, lower]) === higher)
    }
}
