// Mac and iPhone screens. The watch is a genuinely different shape — no
// file exporter, no pasteboard, no keyboard shortcuts — so it gets its own
// views in Watch/ rather than a pile of size guards in these.
#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

/// The focus surface: composer when idle, live session when running, capture
/// sheet on top of either.
public struct FocusScreen: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \PlanBlock.plannedStart) private var blocks: [PlanBlock]
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    private let controller: FocusController
    @State private var now = Date()
    @State private var showsAdHocComposer = false
    @State private var showsBlockEditor = false
    @State private var isChangingActivity = false
    @State private var actualIntent = ""
    @State private var loadError: String?

    public init(controller: FocusController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            theme.canvas.ignoresSafeArea()
            if controller.hasSession {
                RunningSessionView(controller: controller)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if let block = scheduledBlock, !showsAdHocComposer {
                scheduledStart(block)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                VStack(spacing: 0) {
                    if !showsAdHocComposer {
                        Spacer()
                        EmptyStateView(
                            symbol: "calendar.badge.plus",
                            title: "Nothing else is scheduled today",
                            message: "Add a block in Today, or start something unplanned and Anchor will include it in History."
                        )
                        Button("Add a block") { showsBlockEditor = true }
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.top, Space.md)
                        Button("Start something else") { showsAdHocComposer = true }
                            .buttonStyle(QuietButtonStyle())
                        Spacer()
                    } else {
                        StartComposer { goal, intent, minutes, project, notes, tagIDs in
                            _ = withAnimation(Motion.gentle) {
                                controller.start(
                                    goal: goal,
                                    intent: intent,
                                    minutes: minutes,
                                    project: project,
                                    notes: notes,
                                    tagIDStrings: tagIDs
                                )
                            }
                            showsAdHocComposer = false
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.gentle, value: controller.hasSession)
        .task {
            refreshSchedule()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
                refreshSchedule()
            }
        }
        .sheet(isPresented: Binding(
            get: { controller.isCapturing },
            set: { controller.isCapturing = $0 }
        )) {
            CaptureSheet(controller: controller)
                .anchorTheme()
        }
        .sheet(isPresented: $showsBlockEditor) {
            PlanBlockEditor(initialDay: now) { refreshSchedule() }
                .anchorTheme()
        }
        .onChange(of: controller.hasSession) { _, hasSession in
            if !hasSession { refreshSchedule() }
        }
    }

    private var scheduledBlock: PlanBlock? {
        guard let record = ScheduledFocusResolver().nextBlock(from: blocks.map { $0.snapshot() }, now: now) else {
            return nil
        }
        return blocks.first { $0.id == record.id }
    }

    private func scheduledStart(_ block: PlanBlock) -> some View {
        ScrollView {
            VStack(spacing: Space.lg) {
                Spacer(minLength: Space.xl)
                Text(block.plannedStart <= now && now < block.plannedEnd ? "NOW" : (block.plannedStart > now ? "UP NEXT" : "STILL OPEN"))
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(theme.textTertiary)
                Image(systemName: block.kind.symbolName)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(theme.accent)
                    .frame(width: 76, height: 76)
                    .background(theme.accent.opacity(0.12), in: .circle)
                VStack(spacing: Space.xxs) {
                    Text(block.title)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("\(block.plannedStart.formatted(date: .omitted, time: .shortened)) · \(Format.duration(Double(block.plannedSeconds)))")
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.textSecondary)
                }

                if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(theme.negative)
                }

                if isChangingActivity {
                    Card(padding: Space.lg) {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("What are you actually doing?")
                                .font(.headline)
                                .foregroundStyle(theme.textPrimary)
                            TextField("Name the actual activity", text: $actualIntent, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(1...3)
                            Text("Anchor will keep the planned block and record this as a deliberate change for tonight’s comparison.")
                                .font(.footnote)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }

                VStack(spacing: Space.sm) {
                    Button(isChangingActivity ? "Start actual activity" : "Start this block") {
                        start(block)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isChangingActivity && actualIntent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(isChangingActivity ? "Use the scheduled block" : "I’m doing something else") {
                        isChangingActivity.toggle()
                        actualIntent = ""
                    }
                    .buttonStyle(QuietButtonStyle())
                    Button("Start an unplanned block") { showsAdHocComposer = true }
                        .buttonStyle(QuietButtonStyle())
                }
                Text("Once started, Lock a distraction stays on top of the timer with quick interruption options.")
                    .font(.footnote)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(Space.lg)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    private func refreshSchedule() {
        do {
            _ = try DayPlanService(context: context).materialize(day: now)
            reconcileLinkedSessions()
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

    private func start(_ block: PlanBlock) {
        let trimmedActual = actualIntent.trimmingCharacters(in: .whitespacesAndNewlines)
        let intent = isChangingActivity ? trimmedActual : block.title
        guard !intent.isEmpty else { return }
        let session = controller.start(
            goal: nil,
            intent: intent,
            minutes: max(1, Int(ceil(Double(block.plannedSeconds) / 60))),
            notes: block.details
        )
        block.sessionID = session.id
        block.actualStartedAt = session.startedAt
        block.state = .inProgress
        if intent != block.title {
            context.insert(DivergenceEvent(
                blockID: block.id,
                sessionID: session.id,
                kind: .deliberateReplan,
                note: "Did \(intent) instead of \(block.title)."
            ))
        }
        do {
            try context.save()
            loadError = nil
        } catch {
            loadError = "Focus started, but Anchor could not link it to the schedule. It will still appear in History."
        }
        isChangingActivity = false
        actualIntent = ""
    }
}

/// Tabs, shared by both platforms so the two apps stay conceptually identical.
public enum AnchorTab: String, CaseIterable, Identifiable, Sendable {
    case focus, today, habits, history

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .focus: "Focus"
        case .today: "Today"
        case .habits: "Habits"
        case .history: "History"
        }
    }

    public var symbolName: String {
        switch self {
        case .focus: "scope"
        case .today: "calendar"
        case .habits: "repeat"
        case .history: "clock.arrow.circlepath"
        }
    }

    public static func demoValue(_ rawValue: String) -> AnchorTab? {
        switch rawValue {
        case "day": .today
        case "log", "insights": .history
        case "settings": .focus
        default: AnchorTab(rawValue: rawValue)
        }
    }
}

/// The app shell.
///
/// A sidebar on the Mac, tabs on the phone — the platform-native shape in each
/// case, over one shared set of screens.
public struct RootView: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    @AppStorage("anchor.unified-day-onboarding.seen.v1") private var unifiedOnboardingSeen = false
    private let controller: FocusController
    private let storeKind: AnchorStore.StoreKind
    @State private var tab: AnchorTab = .focus
    @State private var showsSettings = false
    @State private var forcedOnboardingFinished = false

    public init(
        controller: FocusController,
        storeKind: AnchorStore.StoreKind = .persistent
    ) {
        self.controller = controller
        self.storeKind = storeKind
        _tab = State(
            initialValue: DemoData.initialTab.flatMap(AnchorTab.demoValue)
                ?? .focus
        )
    }

    public var body: some View {
        Group {
            if controller.hasSession || shouldSkipOnboarding {
                appShell
            } else if (shouldForceOnboarding && !forcedOnboardingFinished) || !unifiedOnboardingSeen {
                AnchorOnboardingView(isExistingOwnerOrientation: !sessions.isEmpty) {
                    unifiedOnboardingSeen = true
                    forcedOnboardingFinished = true
                    tab = .focus
                } onOpenApp: {
                    unifiedOnboardingSeen = true
                    forcedOnboardingFinished = true
                }
            } else {
                appShell
            }
        }
        .onChange(of: activeSessionSignature, initial: true) {
            controller.synchronizeActiveSessionFromStore()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            controller.synchronizeActiveSessionFromStore()
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
        NavigationSplitView {
            List(AnchorTab.allCases, selection: $tab) { item in
                NavigationLink(value: item) {
                    // Unselected icons take the brand grey. Selected rows are
                    // drawn on the accent itself, so the icon has to fall back to
                    // the system's selection foreground or it would be jade on jade.
                    Label {
                        Text(item.label)
                    } icon: {
                        Image(systemName: item.symbolName)
                            .foregroundStyle(
                                tab == item ? AnyShapeStyle(.primary) : AnyShapeStyle(theme.textSecondary)
                            )
                    }
                }
            }
            // Tint on the List itself, not the split view: the selection highlight
            // reads from the List's tint and would otherwise draw system blue the
            // moment the sidebar takes focus.
            .tint(theme.accent)
            .navigationSplitViewColumnWidth(min: 168, ideal: 188, max: 240)
            .safeAreaInset(edge: .bottom) { sidebarStatus }
        } detail: {
            screen(for: tab)
                .navigationTitle(tab.label)
        }
        .tint(theme.accent)
        #else
        TabView(selection: $tab) {
            ForEach(AnchorTab.allCases) { item in
                NavigationStack {
                    screen(for: item)
                        .navigationTitle(item.label)
                }
                .tabItem { Label(item.label, systemImage: item.symbolName) }
                .tag(item)
            }
        }
        .tint(theme.accent)
        #endif
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack { SettingsScreen(storeKind: storeKind) }
                .anchorTheme()
        }
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
            case .today: TodayScreen(controller: controller) { self.tab = .focus }
            case .habits: HabitsScreen()
            case .history: HistoryScreen()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showsSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
    }

    /// A live reminder in the sidebar that a session is running, so switching to
    /// Insights doesn't feel like leaving the timer behind.
    @ViewBuilder
    private var sidebarStatus: some View {
        if controller.hasSession {
            Button {
                tab = .focus
            } label: {
                HStack(spacing: Space.xs) {
                    Circle()
                        .fill(controller.isRunning ? theme.accent : theme.textTertiary)
                        .frame(width: 7, height: 7)
                    Text(Format.clock(
                        controller.session?.account.isOpenEnded == true
                            ? controller.elapsed
                            : controller.remaining
                    ))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}
#endif
