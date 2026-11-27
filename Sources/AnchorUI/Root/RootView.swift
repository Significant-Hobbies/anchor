// Mac and iPhone screens. The watch is a genuinely different shape — no
// file exporter, no pasteboard, no keyboard shortcuts — so it gets its own
// views in Watch/ rather than a pile of size guards in these.
#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

/// Focus opens on the current time slot or a single activity field.
public struct FocusScreen: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    private var calendarVisibility = CalendarBlockVisibility()
    @Query(sort: \PlanBlock.plannedStart) private var blocks: [PlanBlock]
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    private let controller: FocusController
    @State private var now = Date()
    @FocusState private var editingActivity: Bool
    @State private var activity = ""
    @State private var replacingID: UUID?
    @State private var recorded = Set<UUID>()
    @State private var loadError: String?

    public init(controller: FocusController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            theme.canvas.ignoresSafeArea()
            if controller.hasSession {
                RunningSessionView(controller: controller, nextBlock: nextAppointment)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.md) {
                        if let block = scheduledBlock, replacingID != block.id, activity.isEmpty {
                            Text("Scheduled now")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(theme.textSecondary)
                            Text(block.title)
                                .font(.largeTitle.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(block.plannedStart.formatted(date: .omitted, time: .shortened)) – \(block.plannedEnd.formatted(date: .omitted, time: .shortened))")
                                .foregroundStyle(theme.textSecondary)
                            Button("Start focusing") { start(block) }
                                .buttonStyle(PrimaryButtonStyle(expands: false))
                            Button("Do something else") {
                                replacingID = block.id
                                editingActivity = true
                            }
                                .buttonStyle(.plain)
                        } else {
                            TextField("Add an activity", text: $activity, prompt: Text("Add an activity").foregroundColor(theme.textSecondary))
                                .textFieldStyle(.plain)
                                .focused($editingActivity)
                                .padding(.horizontal, Space.md)
                                .frame(minHeight: 44)
                                .background(theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Radius.md)
                                        .strokeBorder(editingActivity ? theme.textSecondary : theme.hairline)
                                        .allowsHitTesting(false)
                                }
                                .submitLabel(.go)
                                .onSubmit(startActivity)
                            HStack(spacing: Space.md) {
                                Button("Start focusing", action: startActivity)
                                    .buttonStyle(PrimaryButtonStyle(expands: false))
                                    .disabled(trimmedActivity.isEmpty)
                                if replacingID != nil {
                                    Button("Cancel") {
                                        activity = ""
                                        replacingID = nil
                                    }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        if let message = loadError ?? controller.lastError {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(theme.negative)
                        }
                    }
                    .frame(maxWidth: 480, alignment: .leading)
                    .padding(Space.lg)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                now = Date()
                refreshSchedule()
                let boundary = blocks.flatMap { [$0.plannedStart, $0.plannedEnd] }.filter { $0 > now }.min()
                let interval = min(30, boundary?.timeIntervalSinceNow ?? 30)
                try? await Task.sleep(for: .seconds(max(0.05, interval)))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .actualEntriesChanged)) { _ in refreshSchedule() }
        .sheet(isPresented: Binding(
            get: { controller.isCapturing },
            set: { controller.isCapturing = $0 }
        )) {
            CaptureSheet(controller: controller)
                .anchorTheme()
        }
        .onChange(of: controller.session?.id) { refreshSchedule() }
    }

    private var trimmedActivity: String {
        activity.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startActivity() {
        guard !controller.hasSession, !trimmedActivity.isEmpty else { return }
        if let block = scheduledBlock, replacingID == block.id {
            start(block, intent: trimmedActivity)
        } else if controller.start(goal: nil, intent: trimmedActivity, minutes: 25) != nil {
            activity = ""
            replacingID = nil
        }
    }

    private var nextAppointment: PlanBlock? {
        calendarVisibility.filter(blocks).first { block in
            block.plannedStart > now && block.state == .planned && !block.isUnplannedTimeLog
                && (block.sessionID == nil || block.sessionID != controller.session?.id)
                && (block.externalEventKey == nil || block.plannedSeconds < 86_400)
        }
    }

    private var scheduledBlock: PlanBlock? {
        let visible = calendarVisibility.filter(blocks)
        let current = ScheduledFocusResolver().nextBlock(from: visible.map { $0.snapshot() }, recorded: recorded, now: now, currentOnly: true)
        return visible.first { $0.id == current?.id }
    }

    private func refreshSchedule() {
        do {
            _ = try DayPlanService(context: context).materialize(day: now)
            reconcileLinkedSessions()
            if let url = context.plannerSidecarURL {
                recorded = Set(try DayLedgerStore(storeURL: url).load().entries.compactMap(\.sourcePlanID))
            }
            loadError = nil
        } catch {
            loadError = "Anchor could not refresh today’s schedule."
        }
    }

    private func reconcileLinkedSessions() {
        for block in blocks {
            guard let sessionID = block.sessionID,
                  let session = sessions.first(where: { $0.id == sessionID }) else { continue }
            block.actualStartedAt = session.startedAt
            if session.state == .finished {
                block.actualEndedAt = session.endedAt
                block.state = .completed
            } else {
                block.state = .inProgress
            }
        }
        if context.hasChanges { try? context.save() }
    }

    private func start(_ block: PlanBlock, intent: String? = nil) {
        guard !controller.hasSession, block.plannedStart <= Date(), Date() < block.plannedEnd else {
            now = Date()
            return
        }
        do {
            try PlanBlockFocusStarter.start(
                block,
                intent: intent,
                controller: controller,
                context: context
            )
            loadError = nil
        } catch {
            loadError = controller.lastError ?? "Anchor could not start this planned session. Please try again."
            return
        }
        replacingID = nil
        activity = ""
    }
}

/// The one schedule-to-timer handoff used by both the main Focus surface and
/// the Mac mini timer. Keeping the link in one place prevents a quick menu-bar
/// start from becoming an unplanned session in the evening review.
@MainActor
enum PlanBlockFocusStarter {
    enum StartFailure: Error { case persistence }

    static func start(
        _ block: PlanBlock,
        intent: String? = nil,
        minutes: Int? = nil,
        controller: FocusController,
        context: ModelContext
    ) throws {
        let resolvedIntent = intent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? block.title
        guard !resolvedIntent.isEmpty else { return }
        let project = try context.fetch(FetchDescriptor<Project>()).first { $0.id == block.projectID }

        guard controller.start(
            goal: nil,
            intent: resolvedIntent,
            minutes: minutes ?? max(1, Int(ceil(Double(block.plannedSeconds) / 60))),
            project: project,
            notes: block.details,
            planBlock: block
        ) != nil else { throw StartFailure.persistence }
    }
}

/// The first view of Focus is a stage, not an empty-state card. It gives the
/// authored scene enough room to carry emotion while the action remains the
/// first operational read. The same component reflows rather than forking the
/// Mac and iPhone product.
public enum AnchorTab: String, CaseIterable, Identifiable, Sendable {
    case focus, today, history

    static let destinations: [AnchorTab] = [.today, .focus, .history]

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .focus: "Focus"
        case .today: "Today"
        case .history: "Analysis"
        }
    }

    public var symbolName: String {
        switch self {
        case .focus: "scope"
        case .today: "calendar"
        case .history: "clock.arrow.circlepath"
        }
    }

    public static func demoValue(_ rawValue: String) -> AnchorTab? {
        switch rawValue {
        case "day": .today
        case "analysis", "log", "insights", "habits": .history
        case "settings": .today
        default: AnchorTab(rawValue: rawValue)
        }
    }
}

/// The app shell.
///
/// An authored responsive rail on the Mac and native tabs on the phone, over
/// one shared set of screens.
enum OnboardingGate {
    static func shouldPresent(
        replayRequested: Bool,
        skipsAutomaticOnboarding: Bool,
        forcesOnboarding: Bool,
        forcedOnboardingFinished: Bool,
        hasCompletedCurrentOnboarding: Bool
    ) -> Bool {
        if replayRequested { return true }
        if skipsAutomaticOnboarding { return false }
        if forcesOnboarding { return !forcedOnboardingFinished }
        return !hasCompletedCurrentOnboarding
    }
}

public struct RootView: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    @Query(sort: \ScheduleTemplate.createdAt) private var reminderTemplates: [ScheduleTemplate]
    @Query(sort: \PlanBlock.plannedStart) private var planBlocks: [PlanBlock]
    @StateObject private var remindersCoordinator = RemindersSyncCoordinator()
    @StateObject private var calendarCoordinator = CalendarSyncCoordinator()
    // The product tour changed materially with the schedule/habit overhaul.
    // A versioned key ensures existing owners see this tour once as well.
    @AppStorage("anchor.product-tour.seen.v4") private var unifiedOnboardingSeen = false
    private var calendarVisibility = CalendarBlockVisibility()
    @AppStorage(PlannerStartReminder.leadKey) private var reminderLead = PlannerStartReminder.defaultLead
    private let notifier: SystemSessionCompletionNotifier?
    private let controller: FocusController
    private let storeKind: AnchorStore.StoreKind
    @Bindable private var navigation: AnchorNavigationModel
    @State private var plannerDay = Date()
    @State private var lastCalendarDay = Date()
    @State private var forcedOnboardingFinished = false
    @State private var presentsOnboarding = false

    public init(
        controller: FocusController,
        storeKind: AnchorStore.StoreKind = .persistent,
        navigation: AnchorNavigationModel,
        notifier: SystemSessionCompletionNotifier? = nil
    ) {
        self.notifier = notifier
        self.controller = controller
        self.storeKind = storeKind
        _navigation = Bindable(wrappedValue: navigation)
    }

    public var body: some View {
        Group {
            if shouldPresentOnboarding {
                onboarding
            } else {
                appShell
            }
        }
        .safeAreaInset(edge: .top) {
            if let warning = AnchorStore.privateNoteStorageWarning {
                Text(warning).font(.caption).padding().accessibilityIdentifier("anchor.private-notes.storage-warning")
            }
        }
        .onChange(of: reminderUpdate, initial: true) { _, update in
            reconcileStartReminders(update)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            #if os(macOS)
            reconcileStartReminders(reminderUpdate)
            #else
            // Refill the operating system’s finite queue as earlier reminders fire.
            while !Task.isCancelled {
                reconcileStartReminders(reminderUpdate)
                try? await Task.sleep(for: .seconds(60))
            }
            #endif
        }
        .onChange(of: activeSessionSignature, initial: true) {
            controller.synchronizeActiveSessionFromStore()
        }
        .onChange(of: planSignature) {
            syncExternal()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in updateCalendarDay() }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            updateCalendarDay()
            if controller.isCapturing { navigation.select(.focus) }
            controller.synchronizeActiveSessionFromStore()
            syncExternal()
        }
    }

    private func updateCalendarDay() {
        let now = Date()
        guard !Calendar.current.isDate(now, inSameDayAs: lastCalendarDay) else { return }
        if Calendar.current.isDate(plannerDay, inSameDayAs: lastCalendarDay) { plannerDay = now }
        lastCalendarDay = now
    }

    private var reminderUpdate: PlannerReminderUpdate {
        guard reminderLead >= 0 else { return PlannerReminderUpdate(entries: [], leadMinutes: reminderLead) }
        let entries = PlannerStartReminder.upcoming(blocks: calendarVisibility.filter(planBlocks), templates: reminderTemplates)
        return PlannerReminderUpdate(entries: entries, leadMinutes: reminderLead)
    }

    private func reconcileStartReminders(_ update: PlannerReminderUpdate) {
        guard storeKind != .inMemory, !CloudKitSchemaSeed.isRequested,
              AnchorExternalSyncPolicy.allowsSessionSynchronization() else { return }
        notifier?.reconcileStartReminders(update, canRequestPermission: scenePhase == .active)
    }

    private func syncExternal() {
        let blocks = planBlocks
        Task {
            await remindersCoordinator.sync(context: context, blocks: blocks)
            await calendarCoordinator.sync(context: context, blocks: blocks)
        }
    }

    private var planSignature: [String] {
        planBlocks.map {
            "\($0.id.uuidString):\($0.updatedAt.timeIntervalSince1970):\($0.stateRaw):\($0.reminderExternalIdentifier ?? "-")"
        }
    }

    private var activeSessionSignature: [String] {
        sessions
            .filter(\.isActive)
            .map { "\($0.id.uuidString):\($0.stateRaw):\($0.runningSince?.timeIntervalSince1970 ?? 0)" }
    }

    @ViewBuilder
    private var appShell: some View {
        Group {
        #if os(macOS)
        MacAppShell(
            selection: Binding(
                get: { navigation.selectedTab },
                set: { newValue in
                    navigation.select(newValue)
                }
            ),
            controller: controller,
            isSettingsSelected: navigation.showsSettings,
            onSettings: { navigation.showSettings() }
        ) {
            if navigation.showsSettings {
                SettingsScreen(storeKind: storeKind, onShowOnboarding: showOnboarding, remindersCoordinator: remindersCoordinator, calendarCoordinator: calendarCoordinator)
            } else {
                screen(for: navigation.selectedTab)
            }
        }
        .tint(theme.accent)
        #else
        TabView(selection: $navigation.selectedTab) {
            ForEach(AnchorTab.destinations) { item in
                NavigationStack {
                    screen(for: item)
                        .navigationTitle(item == .history ? "Insights" : item.label)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button { navigation.showSettings() } label: {
                                    Label("settings", systemImage: "gearshape")
                                }
                                .accessibilityIdentifier("anchor.toolbar.settings")
                                .help("Open Settings")
                            }
                        }
                        .navigationDestination(isPresented: $navigation.showsSettings) {
                            SettingsScreen(storeKind: storeKind, onShowOnboarding: showOnboarding, remindersCoordinator: remindersCoordinator, calendarCoordinator: calendarCoordinator)
                                .navigationTitle("settings")
                                .toolbar(.hidden, for: .tabBar)
                        }
                }
                .tabItem { Label(item.label.lowercased(), systemImage: item.symbolName)
                    .accessibilityLabel(item.label) }
                .tag(item)
            }
        }
        .tint(theme.accent)
        #endif
        }
        .onChange(of: controller.isCapturing) { _, capturing in
            if capturing && scenePhase == .active { navigation.select(.focus) }
        }
    }

    private var onboarding: some View {
        AnchorOnboardingView(isExistingOwnerOrientation: !sessions.isEmpty) {
            finishOnboarding()
        } onOpenApp: {
            finishOnboarding()
        }
    }

    private func showOnboarding() {
        navigation.showsSettings = false
        presentsOnboarding = true
    }

    private var shouldPresentOnboarding: Bool {
        OnboardingGate.shouldPresent(
            replayRequested: presentsOnboarding,
            skipsAutomaticOnboarding: shouldSkipOnboarding,
            forcesOnboarding: shouldForceOnboarding,
            forcedOnboardingFinished: forcedOnboardingFinished,
            hasCompletedCurrentOnboarding: unifiedOnboardingSeen
        )
    }

    private func finishOnboarding() {
        if !shouldForceOnboarding {
            unifiedOnboardingSeen = true
        }
        forcedOnboardingFinished = true
        presentsOnboarding = false
        navigation.select(.today)
    }

    private var shouldForceOnboarding: Bool {
        ProcessInfo.processInfo.environment["ANCHOR_ONBOARDING_DEMO"] == "1"
    }

    private var shouldSkipOnboarding: Bool {
        ProcessInfo.processInfo.environment["ANCHOR_ONBOARDING_SKIP"] == "1"
    }

    @ViewBuilder
    private func screen(for tab: AnchorTab) -> some View {
        Group {
            switch tab {
            case .focus: FocusScreen(controller: controller)
            case .today: PlanScreen(controller: controller, calendarCoordinator: calendarCoordinator, day: $plannerDay) { navigation.select(.focus) }
            case .history: AnalyticsScreen()
            }
        }
    }
}
#endif
