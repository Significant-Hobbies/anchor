import AnchorCore
import AnchorUI
import AppKit
import CoreGraphics
import SwiftData
import SwiftUI
import UserNotifications

/// The Mac app: a normal window plus a menu-bar presence, because the whole
/// point is that the timer stays reachable while you work in something else.
@main
struct AnchorMacApp: App {
    @State private var world: AnchorWorld
    @State private var platform: AnchorPlatformSync
    @Environment(\.openWindow) private var openWindow

    init() {
        let world = AnchorWorld()
        _world = State(initialValue: world)
        _platform = State(initialValue: AnchorPlatformSync(context: world.container.mainContext))
    }

    /// Raise the main window from the menu bar. Activation is explicit because a
    /// menu-bar app is not frontmost when the panel is showing.
    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        // Identified so the menu-bar panel can raise it with `openWindow(id:)`.
        WindowGroup(id: "main") {
            RootView(controller: world.controller, storeKind: world.storeKind)
                .anchorTheme()
                .environment(\.anchorPlatformSync, platform)
                .task {
                    // Register after launch so SwiftData's CloudKit mirror can
                    // receive silent pushes while the Mac app stays open.
                    NSApplication.shared.registerForRemoteNotifications()
                    await platform.restoreAndSynchronize()
                }
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
    let machineActivityMonitor: MachineActivityMonitor

    init() {
        #if ANCHOR_LOCAL_ONLY
        let (container, kind) = AnchorStore.makeLocalResilientContainer()
        #else
        let (container, kind) = AnchorStore.makeResilientContainer()
        #endif
        self.container = container
        self.storeKind = kind
        if DemoData.isRequested {
            DemoData.seedIfNeeded(into: container.mainContext)
        }
        let controller = FocusController(
            context: container.mainContext,
            completionNotifier: SystemSessionCompletionNotifier()
        )
        self.controller = controller
        self.machineActivityMonitor = MachineActivityMonitor(
            context: container.mainContext,
            controller: controller
        )
    }
}

/// A deliberately low-resolution presence monitor. It reads only how many
/// seconds have passed since any keyboard/mouse event; it never sees the event,
/// key, app, window, website, or pointer location.
@MainActor
final class MachineActivityMonitor {
    private weak var controller: FocusController?
    private let recorder: MachineActivityRecorder
    private var task: Task<Void, Never>?
    private var untrackedActiveSince: Date?
    private var lastReminderAt: Date?

    init(context: ModelContext, controller: FocusController) {
        self.controller = controller
        self.recorder = MachineActivityRecorder(context: context)
        self.task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func sample(at timestamp: Date = Date()) {
        guard let controller else { return }
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: .null
        )
        recorder.observe(idleSeconds: idleSeconds, isTracking: controller.isRunning, at: timestamp)
        controller.observeMachineIdle(seconds: idleSeconds, at: timestamp)

        let isActivelyUntracked = idleSeconds < 60 && !controller.isRunning
        guard isActivelyUntracked else {
            untrackedActiveSince = nil
            return
        }
        if untrackedActiveSince == nil { untrackedActiveSince = timestamp }
        guard let untrackedActiveSince,
              timestamp.timeIntervalSince(untrackedActiveSince) >= 5 * 60,
              lastReminderAt.map({ timestamp.timeIntervalSince($0) >= 30 * 60 }) ?? true
        else { return }

        lastReminderAt = timestamp
        notifyUntrackedTime()
    }

    private func notifyUntrackedTime() {
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                let allowed = try await center.requestAuthorization(options: [.alert, .sound])
                guard allowed, !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = "Active time isn’t being logged"
                content.body = "Start an Anchor session if this work should be paid."
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: "anchor.machine-activity.untracked",
                    content: content,
                    trigger: nil
                )
                try await center.add(request)
            } catch {
                // Presence reminders are supplementary and permission may be denied.
            }
        }
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
