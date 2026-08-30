#if !os(watchOS)
import AnchorCore
import Foundation
import Observation
import SwiftData
import SwiftUI

#if os(macOS)
import CoreGraphics
import UserNotifications
#endif

/// The one process-lifetime world used by both the Mac and iPhone shells.
/// Platform differences are injected here; product state and screens stay shared.
@MainActor
@Observable
public final class AnchorAppWorld {
    public enum PersistenceMode: Sendable {
        case automatic
        case localOnly
    }

    public let container: ModelContainer
    public let controller: FocusController
    public let storeKind: AnchorStore.StoreKind
    public let platform: AnchorPlatformSync
    public let navigation: AnchorNavigationModel

    #if os(macOS)
    private let machineActivityMonitor: MachineActivityMonitor
    #endif

    public init(persistenceMode: PersistenceMode = .automatic) {
        let result: (container: ModelContainer, kind: AnchorStore.StoreKind)
        switch persistenceMode {
        case .automatic:
            result = AnchorStore.makeResilientContainer()
        case .localOnly:
            result = AnchorStore.makeLocalResilientContainer()
        }

        container = result.container
        storeKind = result.kind
        navigation = AnchorNavigationModel(
            selectedTab: DemoData.initialTab.flatMap(AnchorTab.demoValue) ?? .focus
        )
        if CloudKitSchemaSeed.isRequested {
            do {
                try CloudKitSchemaSeed.seedIfNeeded(into: result.container.mainContext)
            } catch {
                fatalError("Anchor could not save its CloudKit schema seed: \(error)")
            }
        } else if DemoData.isRequested {
            DemoData.seedIfNeeded(into: result.container.mainContext)
        }

        #if os(iOS)
        let focusController = FocusController(
            context: result.container.mainContext,
            completionNotifier: SystemSessionCompletionNotifier(),
            liveActivityCoordinator: ActivityKitLiveActivityCoordinator()
        )
        #else
        let focusController = FocusController(
            context: result.container.mainContext,
            completionNotifier: SystemSessionCompletionNotifier()
        )
        #endif
        controller = focusController

        platform = AnchorPlatformSync(context: result.container.mainContext)

        #if os(macOS)
        machineActivityMonitor = MachineActivityMonitor(
            context: result.container.mainContext,
            controller: focusController
        )
        #endif
    }
}

/// The identical product root used by the Mac and iPhone WindowGroups.
public struct AnchorProductRoot: View {
    private let world: AnchorAppWorld

    public init(world: AnchorAppWorld) {
        self.world = world
    }

    public var body: some View {
        RootView(
            controller: world.controller,
            storeKind: world.storeKind,
            navigation: world.navigation
        )
            .anchorAppearance()
            .environment(\.anchorPlatformSync, world.platform)
            .task { await world.platform.restoreAndSynchronize() }
    }
}

/// Process-lifetime navigation shared by the app window and native Mac menus.
/// Keeping it outside focused values means commands still work from the mini
/// timer and can restore a closed main window at the requested destination.
@MainActor
@Observable
public final class AnchorNavigationModel {
    public var selectedTab: AnchorTab
    public var showsSettings = false

    public init(selectedTab: AnchorTab = .focus) {
        self.selectedTab = selectedTab
    }

    public func select(_ tab: AnchorTab) {
        selectedTab = tab
        showsSettings = false
    }

    public func showSettings() {
        showsSettings = true
    }
}

#if os(macOS)
/// A deliberately low-resolution presence monitor. It reads only how many
/// seconds have passed since any keyboard or mouse event; it never sees the
/// event, key, app, window, website, or pointer location.
@MainActor
private final class MachineActivityMonitor {
    private weak var controller: FocusController?
    private let recorder: MachineActivityRecorder
    private var task: Task<Void, Never>?
    private var untrackedActiveSince: Date?
    private var lastReminderAt: Date?

    init(context: ModelContext, controller: FocusController) {
        self.controller = controller
        recorder = MachineActivityRecorder(context: context)
        task = Task { @MainActor [weak self] in
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
#endif
#endif
