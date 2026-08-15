import AnchorCore
import AnchorUI
import AppKit
import SwiftData
import SwiftUI

/// The Mac app: a normal window plus a menu-bar presence, because the whole
/// point is that the timer stays reachable while you work in something else.
@main
struct AnchorMacApp: App {
    @State private var world = AnchorWorld()
    @Environment(\.openWindow) private var openWindow

    /// Raise the main window from the menu bar. Activation is explicit because a
    /// menu-bar app is not frontmost when the panel is showing.
    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        // Identified so the menu-bar panel can raise it with `openWindow(id:)`.
        WindowGroup(id: "main") {
            RootView(controller: world.controller)
                .anchorTheme()
                .frame(minWidth: 720, minHeight: 560)
        }
        .modelContainer(world.container)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Lock a Distraction") {
                    world.controller.beginManualCapture()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(!world.controller.hasSession)

                Divider()

                Button(world.controller.isPaused ? "Resume Session" : "Pause Session") {
                    world.controller.isPaused ? world.controller.resume() : world.controller.pause()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!world.controller.hasSession)

                Button("End Session") {
                    world.controller.end(reason: .endedEarly)
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!world.controller.hasSession)
            }
        }

        // The same compact surface as a detachable floating window, for people
        // whose menu bar is already full — and it keeps the mini UI reachable
        // when the menu-bar item is hidden behind the overflow chevron.
        Window("Mini Timer", id: "compact") {
            CompactPanel(
                controller: world.controller,
                onOpenWindow: { openMainWindow() }
            )
            .anchorTheme()
            .modelContainer(world.container)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
        .keyboardShortcut("0", modifiers: .command)

        MenuBarExtra {
            CompactPanel(
                controller: world.controller,
                onOpenWindow: { openMainWindow() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
            .anchorTheme()
            .modelContainer(world.container)
        } label: {
            MenuBarLabel(controller: world.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the container and the controller for the process lifetime.
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

/// What sits in the menu bar. Shows the countdown while running so you never
/// have to switch windows to know where you are.
struct MenuBarLabel: View {
    let controller: FocusController

    var body: some View {
        if controller.hasSession {
            let seconds = controller.session?.account.isOpenEnded == true
                ? controller.elapsed
                : controller.remaining
            Label {
                Text(Format.clock(seconds)).monospacedDigit()
            } icon: {
                Image(systemName: controller.isPaused ? "pause.circle" : "scope")
            }
        } else {
            Image(systemName: "scope")
        }
    }
}
