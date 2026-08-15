import AnchorCore
import AnchorUI
import SwiftData
import SwiftUI

/// The iOS app. Same screens, same store, native shell.
@main
struct AnchorIOSApp: App {
    @State private var world = AnchorWorld()

    var body: some Scene {
        WindowGroup {
            RootView(controller: world.controller)
                .anchorTheme()
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
        self.controller = FocusController(context: container.mainContext)
    }
}
