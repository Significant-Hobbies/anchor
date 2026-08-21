import AnchorCore
import AnchorUI
import SwiftData
import SwiftUI

/// The watch app. Shares the same CloudKit-backed store as the phone and Mac,
/// so a session started anywhere is the session you see here.
@main
struct AnchorWatchApp: App {
    @State private var world = AnchorWatchWorld()

    var body: some Scene {
        WindowGroup {
            WatchRootView(controller: world.controller)
                .anchorTheme()
        }
        .modelContainer(world.container)
    }
}

@MainActor
@Observable
final class AnchorWatchWorld {
    let container: ModelContainer
    let controller: FocusController

    init() {
        let (container, _) = AnchorStore.makeResilientContainer()
        self.container = container
        if DemoData.isRequested {
            DemoData.seedIfNeeded(into: container.mainContext)
        }
        // watchOS has no `SystemLanguageModel`, so tagging here is rule-based by
        // construction. The phone or Mac refines it after the store syncs.
        self.controller = FocusController(
            context: container.mainContext,
            tagger: TaggingService(allowsOnDeviceModel: false),
            completionNotifier: SystemSessionCompletionNotifier()
        )
    }
}
