import AnchorUI
import SwiftData
import SwiftUI
import UIKit

/// The iOS app. Same screens, same store, native shell.
@main
struct AnchorIOSApp: App {
    @State private var world: AnchorAppWorld

    init() {
        _world = State(initialValue: makeAnchorAppWorld())
    }

    var body: some Scene {
        WindowGroup {
            AnchorProductRoot(world: world)
                .task {
                    UIApplication.shared.registerForRemoteNotifications()
                }
        }
        .modelContainer(world.container)
    }
}
