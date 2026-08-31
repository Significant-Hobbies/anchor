import Foundation
import Testing

@testable import AnchorUI

@Suite("Shared app architecture")
struct AppArchitectureTests {
    @Test("Onboarding depends on completion, never existing planner data")
    func onboardingGateUsesOnlyCurrentCompletionState() {
        #expect(OnboardingGate.shouldPresent(
            replayRequested: false,
            skipsAutomaticOnboarding: false,
            forcesOnboarding: false,
            forcedOnboardingFinished: false,
            hasCompletedCurrentOnboarding: false
        ))
        #expect(!OnboardingGate.shouldPresent(
            replayRequested: false,
            skipsAutomaticOnboarding: false,
            forcesOnboarding: false,
            forcedOnboardingFinished: false,
            hasCompletedCurrentOnboarding: true
        ))
        #expect(OnboardingGate.shouldPresent(
            replayRequested: true,
            skipsAutomaticOnboarding: true,
            forcesOnboarding: false,
            forcedOnboardingFinished: false,
            hasCompletedCurrentOnboarding: true
        ))
        #expect(OnboardingGate.shouldPresent(
            replayRequested: false,
            skipsAutomaticOnboarding: false,
            forcesOnboarding: true,
            forcedOnboardingFinished: false,
            hasCompletedCurrentOnboarding: false
        ))
        #expect(!OnboardingGate.shouldPresent(
            replayRequested: false,
            skipsAutomaticOnboarding: false,
            forcesOnboarding: true,
            forcedOnboardingFinished: true,
            hasCompletedCurrentOnboarding: false
        ))
    }

    @Test("Mac and iPhone are thin shells over the same product root")
    func fullAppsUseSharedRoot() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shellPaths = [
            repository.appending(path: "Apps/Mac/AnchorMacApp.swift"),
            repository.appending(path: "Apps/iOS/AnchorIOSApp.swift"),
        ]

        for path in shellPaths {
            let source = try String(contentsOf: path, encoding: .utf8)
            #expect(source.contains("AnchorProductRoot(world: world)"))
            #expect(!source.contains("RootView("))
            #expect(!source.contains("AnchorPlatformSync("))
            #expect(!source.contains("preferredColorScheme"))
        }
    }

    @Test("The Mac app is a single-window utility with discoverable native commands")
    func macUsesOneWindowAndNativeMenus() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appending(path: "Apps/Mac/AnchorMacApp.swift"),
            encoding: .utf8
        )

        #expect(source.contains("Window(\"Anchor\", id: \"main\")"))
        #expect(!source.contains("WindowGroup(id: \"main\")"))
        #expect(source.contains("CommandMenu(\"Navigate\")"))
        #expect(source.contains("CommandMenu(\"Focus\")"))
        #expect(source.contains("CommandGroup(replacing: .appSettings)"))
    }

    @Test("Local-only build selection is shared by both full apps")
    func buildConfigurationUsesSharedFactory() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let factory = try String(
            contentsOf: repository.appending(path: "Apps/Shared/AnchorApplication.swift"),
            encoding: .utf8
        )

        #expect(factory.contains("func makeAnchorAppWorld() -> AnchorAppWorld"))
        #expect(factory.contains("ANCHOR_LOCAL_ONLY"))
    }

    @Test("Unsigned Mac builds cannot masquerade as the installed Anchor app")
    func macLocalBuildHasDistinctIdentity() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(
            contentsOf: repository.appending(path: "Apps/project.yml"),
            encoding: .utf8
        )
        let macTarget = try #require(
            project.split(separator: "  AnchorIOS:", maxSplits: 1).first.map(String.init)
        )

        #expect(macTarget.contains("PRODUCT_NAME: Anchor Local"))
        #expect(macTarget.contains("PRODUCT_BUNDLE_IDENTIFIER: com.significanthobbies.anchor.local"))
        #expect(macTarget.contains("CFBundleDisplayName: $(PRODUCT_NAME)"))
    }

    @Test("Flexible habits remain available until explicitly completed or placed")
    func habitsStayDistinctFromTimedScheduleBlocks() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let model = try String(
            contentsOf: repository.appending(path: "Sources/AnchorCore/Planning/DayPlan.swift"),
            encoding: .utf8
        )
        let lifecycle = try String(
            contentsOf: repository.appending(path: "Sources/AnchorCore/Planning/DailyPlanLifecycle.swift"),
            encoding: .utf8
        )
        let today = try String(
            contentsOf: repository.appending(path: "Sources/AnchorUI/Planning/DayScreen.swift"),
            encoding: .utf8
        )

        #expect(model.contains("public var habitUsesSuggestedTime: Bool = true"))
        #expect(model.contains("public final class HabitCompletion"))
        #expect(model.contains("!template.isBehaviorHabit && template.applies"))
        #expect(lifecycle.contains("public struct HabitDayService"))
        #expect(today.contains("anchor.today.habits"))
        #expect(today.contains("anchor.today.habit.place"))
        #expect(today.contains("A suggestion, never a reservation"))
        #expect(today.contains("available all day"))
        #expect(model.contains("case .saturday: \"Sat\""))
    }
}
