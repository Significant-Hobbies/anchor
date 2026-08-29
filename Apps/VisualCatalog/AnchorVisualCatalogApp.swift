import AnchorCore
import AnchorUI
import AppKit
import SwiftData
import SwiftUI

@main
@MainActor
struct AnchorVisualCatalogApp: App {
    init() {
        DispatchQueue.main.async {
            do {
                try VisualCatalogRenderer().render()
                NSApplication.shared.terminate(nil)
            } catch {
                FileHandle.standardError.write(Data("Anchor visual catalog failed: \(error)\n".utf8))
                NSApplication.shared.terminate(nil)
            }
        }
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
private struct VisualCatalogRenderer {
    private struct RenderSpec {
        let name: String
        let width: CGFloat
        let height: CGFloat
        let content: () -> AnyView
    }

    private struct Manifest: Encodable {
        let generatedAt: Date
        let renderPlatform: String
        let store: String
        let pages: [Page]

        struct Page: Encodable {
            let name: String
            let width: Int
            let height: Int
            let file: String
        }
    }

    private enum RenderError: Error {
        case missingImage(String)
        case missingTIFF(String)
        case missingPNG(String)
    }

    func render() throws {
        let output = outputDirectory()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = container.mainContext
        DemoData.seedIfNeeded(into: context)
        seedCurrentDay(into: context)
        let controller = FocusController(context: context)
        let platform = AnchorPlatformSync(
            context: context,
            enabled: false,
            sessionSynchronizationEnabled: false
        )

        let specs = renderSpecs(
            container: container,
            controller: controller,
            platform: platform
        )
        var pages: [Manifest.Page] = []

        for spec in specs {
            let fileName = "\(spec.name).png"
            let fileURL = output.appending(path: fileName)
            try render(spec, to: fileURL)
            pages.append(.init(
                name: spec.name,
                width: Int(spec.width),
                height: Int(spec.height),
                file: fileName
            ))
        }

        let manifest = Manifest(
            generatedAt: Date(),
            renderPlatform: "macOS offscreen render of shared Anchor surfaces",
            store: "ephemeral in-memory demo data",
            pages: pages
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: output.appending(path: "manifest.json"))
        print("Rendered \(pages.count) Anchor surfaces to \(output.path)")
    }

    private func renderSpecs(
        container: ModelContainer,
        controller: FocusController,
        platform: AnchorPlatformSync
    ) -> [RenderSpec] {
        func page(
            _ name: String,
            width: CGFloat,
            height: CGFloat,
            @ViewBuilder content: @escaping () -> some View
        ) -> RenderSpec {
            RenderSpec(name: name, width: width, height: height) {
                AnyView(
                    content()
                        .modelContainer(container)
                        .environment(\.anchorTheme, .dark)
                        .environment(\.anchorWorkspaceMaxWidth, min(width, 960))
                        .environment(\.anchorPlatformSync, platform)
                        .preferredColorScheme(.dark)
                        .frame(width: width, height: height)
                )
            }
        }

        return [
            page("focus-phone", width: 402, height: 874) {
                FocusScreen(controller: controller)
            },
            page("focus-mac", width: 1_200, height: 800) {
                FocusScreen(controller: controller)
            },
            page("today-phone", width: 402, height: 874) {
                TodayScreen(controller: controller, onOpenFocus: {})
            },
            page("today-mac", width: 1_200, height: 800) {
                TodayScreen(controller: controller, onOpenFocus: {})
            },
            page("habits-phone", width: 402, height: 874) {
                HabitsScreen()
            },
            page("habits-mac", width: 1_200, height: 800) {
                HabitsScreen()
            },
            page("history-day-phone", width: 402, height: 874) {
                HistoryScreen(section: .day)
            },
            page("history-day-mac", width: 1_200, height: 800) {
                HistoryScreen(section: .day)
            },
            page("history-interruptions-mac", width: 1_200, height: 800) {
                HistoryScreen(section: .interruptions)
            },
            page("history-interruptions-phone", width: 402, height: 874) {
                HistoryScreen(section: .interruptions)
            },
            page("history-trends-mac", width: 1_200, height: 800) {
                HistoryScreen(section: .trends)
            },
            page("history-trends-phone", width: 402, height: 874) {
                HistoryScreen(section: .trends)
            },
            page("settings-phone", width: 402, height: 874) {
                SettingsScreen(storeKind: .inMemory, onShowOnboarding: {})
            },
            page("settings-mac", width: 1_200, height: 800) {
                SettingsScreen(storeKind: .inMemory, onShowOnboarding: {})
            },
            page("onboarding-phone", width: 402, height: 874) {
                AnchorOnboardingView(onComplete: {})
            },
            page("onboarding-mac", width: 1_200, height: 800) {
                AnchorOnboardingView(onComplete: {})
            },
            page("compact-panel", width: 300, height: 230) {
                CompactPanel(controller: controller, onOpenWindow: {})
            },
            page("editor-block-mac", width: 720, height: 760) {
                AnchorVisualCatalogSheet(.blockEditor)
            },
            page("editor-habit-mac", width: 720, height: 760) {
                AnchorVisualCatalogSheet(.habitEditor)
            },
            page("editor-patterns-mac", width: 760, height: 760) {
                AnchorVisualCatalogSheet(.behaviorProfile)
            },
            page("editor-metadata-mac", width: 660, height: 680) {
                AnchorVisualCatalogSheet(.metadataLibrary)
            },
        ]
    }

    private func render(_ spec: RenderSpec, to url: URL) throws {
        let host = NSHostingView(rootView: spec.content())
        host.frame = NSRect(x: 0, y: 0, width: spec.width, height: spec.height)
        host.wantsLayer = true
        host.layer?.contentsScale = 2

        // Native List and navigation content only materialize inside a window
        // hierarchy. This panel is never ordered front or made key, and lives
        // far outside every display, so it cannot cover work or take focus.
        let panel = NSPanel(
            contentRect: NSRect(x: -20_000, y: -20_000, width: spec.width, height: spec.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        defer {
            panel.contentView = nil
            panel.close()
        }
        host.layoutSubtreeIfNeeded()

        // Give SwiftUI queries and on-appear work one main-run-loop turn without
        // ever attaching the view to a visible window.
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        host.layoutSubtreeIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        else { throw RenderError.missingImage(spec.name) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:])
        else { throw RenderError.missingPNG(spec.name) }
        try png.write(to: url)
    }

    private func outputDirectory() -> URL {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--output"), arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "artifacts/design/visual-catalog")
    }

    private func seedCurrentDay(into context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = ScheduleWeekday(day: today, calendar: calendar)

        let movement = ScheduleTemplate(
            title: "Take a walk outside",
            details: "A small reset that can fit anywhere today.",
            startMinutesFromMidnight: 1_020,
            plannedSeconds: 1_200,
            weekdays: [weekday],
            kind: .routine,
            flexibility: .flexible,
            behaviorPattern: .shortVideo,
            lifeDirection: .movement,
            isBehaviorHabit: true,
            habitUsesSuggestedTime: false
        )
        let reading = ScheduleTemplate(
            title: "Read for twenty minutes",
            details: "Keep the phone in another room.",
            startMinutesFromMidnight: 1_200,
            plannedSeconds: 1_200,
            weekdays: [weekday],
            kind: .routine,
            flexibility: .flexible,
            behaviorPattern: .socialFeeds,
            lifeDirection: .calm,
            isBehaviorHabit: true,
            habitUsesSuggestedTime: true
        )
        context.insert(movement)
        context.insert(reading)
        context.insert(HabitCompletion(habitID: movement.id, day: today))

        let start = calendar.date(bySettingHour: 10, minute: 30, second: 0, of: today) ?? today
        context.insert(PlanBlock(
            title: "Finish the launch brief",
            details: "Resolve the final product decisions.",
            plannedStart: start,
            plannedSeconds: 3_600,
            kind: .focus,
            flexibility: .flexible
        ))
        context.insert(BehaviorProfile(
            selectedPatterns: [.shortVideo, .socialFeeds],
            desiredDirections: [.movement, .calm, .focus]
        ))
        try? context.save()
    }
}
