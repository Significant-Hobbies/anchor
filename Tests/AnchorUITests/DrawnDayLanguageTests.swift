import Foundation
import Testing

@Suite("Drawn Day visual language")
struct DrawnDayLanguageTests {
    @Test("The core loop shares the line, knot, and trace materials")
    func coreLoopUsesSharedMaterials() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let components = try source("Sources/AnchorUI/Design/Components.swift", in: repository)
        let focus = try source("Sources/AnchorUI/Root/RootView.swift", in: repository)
        let running = try source("Sources/AnchorUI/Focus/RunningSessionView.swift", in: repository)
        let day = try source("Sources/AnchorUI/Planning/DayScreen.swift", in: repository)

        #expect(components.contains("public struct DrawnTrace"))
        #expect(components.contains("public struct InterruptionKnotMark"))
        #expect(focus.contains("FocusPreludeStage"))
        #expect(running.contains("InterruptionKnotMark"))
        #expect(day.contains("DayRailSegment"))
        #expect(day.contains("DrawnTrace(fraction:"))
    }

    @Test("Default-dark primary doodles have real luminosity variants")
    func primaryDoodlesHaveDarkVariants() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for asset in ["FocusDoodle", "TodayDoodle"] {
            let contents = try source(
                "Apps/Shared/Assets.xcassets/\(asset).imageset/Contents.json",
                in: repository
            )
            #expect(contents.contains("\"appearance\" : \"luminosity\""))
            #expect(contents.contains("-dark.png"))
        }
    }

    @Test("Preference primitives stay product-agnostic and Settings adapts as one screen")
    func settingsUsesExtractionReadyPrimitives() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let components = try source(
            "Sources/AnchorUI/Design/PreferenceComponents.swift",
            in: repository
        )
        let settings = try source("Sources/AnchorUI/Root/SettingsScreen.swift", in: repository)

        #expect(!components.contains("import AnchorCore"))
        #expect(components.contains("public struct PreferenceGroup"))
        #expect(components.contains("public struct PreferenceActionRow"))
        #expect(settings.contains("if workspaceMaxWidth >= 900"))
        #expect(settings.contains("primarySettingsColumn"))
        #expect(settings.contains("secondarySettingsColumn"))
    }

    @Test("Onboarding and Settings share one optional private Hub account experience")
    func accountJourneyUsesOneSharedPanel() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let account = try source(
            "Sources/AnchorUI/Account/HubAccountPanel.swift",
            in: repository
        )
        let onboarding = try source(
            "Sources/AnchorUI/Onboarding/AnchorOnboardingView.swift",
            in: repository
        )
        let settings = try source("Sources/AnchorUI/Root/SettingsScreen.swift", in: repository)

        #expect(account.contains("public struct HubAccountPanel"))
        #expect(account.contains("goal, timing, outcome, and interruption count"))
        #expect(account.contains("Image(\"GoogleSignInMark\")"))
        #expect(onboarding.contains("presentation: .onboarding"))
        #expect(onboarding.contains("Continue locally"))
        #expect(settings.contains("presentation: .settings"))
        #expect(!onboarding.contains("SignInWithAppleButton"))
        #expect(!settings.contains("SignInWithAppleButton"))
    }

    @Test("Onboarding centers responsively and Mac keeps native window chrome")
    func onboardingUsesViewportCenterAndNativeMacChrome() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let onboarding = try source(
            "Sources/AnchorUI/Onboarding/AnchorOnboardingView.swift",
            in: repository
        )
        let macApp = try source("Apps/Mac/AnchorMacApp.swift", in: repository)

        #expect(onboarding.contains("minHeight: max(0, proxy.size.height - Space.xxl)"))
        #expect(!macApp.contains(".windowStyle(.hiddenTitleBar)"))
    }

    @Test("Mac navigation uses one selected surface")
    func macNavigationAvoidsStackedSelectionMarks() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shell = try source("Sources/AnchorUI/Root/MacAppShell.swift", in: repository)

        #expect(shell.contains(".fill(backgroundColor)"))
        #expect(!shell.contains("metricsEdgeOffset"))
        #expect(!shell.contains("if isSelected && presentation != .icons"))
    }

    @Test("Onboarding QA cannot consume the owner's first-run state")
    func onboardingDemoKeepsPersistentTourStateUntouched() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = try source("Sources/AnchorUI/Root/RootView.swift", in: repository)
        let onboarding = try source(
            "Sources/AnchorUI/Onboarding/AnchorOnboardingView.swift",
            in: repository
        )

        #expect(root.contains("anchor.product-tour.seen.v3"))
        #expect(root.contains("if !shouldForceOnboarding"))
        #expect(onboarding.contains("if !isDemo { savedUnifiedStep = step.rawValue }"))
        #expect(onboarding.contains("if !isDemo { savedStep = step.rawValue }"))
    }

    private func source(_ path: String, in repository: URL) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }
}
