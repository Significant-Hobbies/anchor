import AnchorCore
import AnchorUI
import SwiftData
import SwiftUI

/// The iOS app. Same screens, same store, native shell.
@main
struct AnchorIOSApp: App {
    @State private var world: AnchorWorld
    @State private var platform: AnchorPlatformSync

    init() {
        let world = AnchorWorld()
        _world = State(initialValue: world)
        _platform = State(initialValue: AnchorPlatformSync(context: world.container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView(controller: world.controller)
                .anchorTheme()
                .environment(\.anchorPlatformSync, platform)
                .task { await platform.restoreAndSynchronize() }
        }
        .modelContainer(world.container)
    }
}

@MainActor
@Observable
final class AnchorWorld {
    let container: ModelContainer
    let controller: FocusController
    let storeKind: AnchorStore.StoreKind

    init() {
        let (container, kind) = AnchorStore.makeResilientContainer()
        self.container = container
        self.storeKind = kind
        if DemoData.isRequested {
            DemoData.seedIfNeeded(into: container.mainContext)
        }
        let controller = FocusController(
            context: container.mainContext,
            completionNotifier: SystemSessionCompletionNotifier(),
            liveActivityCoordinator: ActivityKitLiveActivityCoordinator()
        )
        self.controller = controller
    }
}
