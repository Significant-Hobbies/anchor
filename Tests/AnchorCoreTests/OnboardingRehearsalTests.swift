import Testing

@testable import AnchorCore

@Suite("Onboarding rehearsal")
struct OnboardingRehearsalTests {
    @Test("Park and return discards the captured thought from live rehearsal state")
    func parkAndReturnIsEphemeral() throws {
        var rehearsal = OnboardingRehearsal()

        let began = rehearsal.begin(goal: "Finish the release")
        #expect(began)
        rehearsal.openCapture()
        rehearsal.updateThought("Check the build status")
        let parked = rehearsal.parkAndReturn()
        let receipt = try #require(parked)

        #expect(receipt.goal == "Finish the release")
        #expect(receipt.recoveredThought == "Check the build status")
        #expect(rehearsal.thought.isEmpty)
        #expect(rehearsal.step == .returned)
    }

    @Test("Blank goals and thoughts cannot advance the rehearsal")
    func blankValuesDoNotAdvance() {
        var rehearsal = OnboardingRehearsal()

        let beganBlank = rehearsal.begin(goal: "   ")
        #expect(!beganBlank)
        #expect(rehearsal.step == .goal)
        let began = rehearsal.begin(goal: "Write the proposal")
        #expect(began)
        rehearsal.openCapture()
        rehearsal.updateThought("\n")
        let parked = rehearsal.parkAndReturn()
        #expect(parked == nil)
        #expect(rehearsal.step == .capture)
    }
}
