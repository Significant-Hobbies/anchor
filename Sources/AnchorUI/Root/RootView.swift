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
                        FocusPreludeStage(
                            eyebrow: "Focus",
                            title: "Begin with one clear thing",
                            message: "No block is waiting for you. Name what matters now, and Anchor will hold everything else at the edge."
                        ) {
                            #if os(macOS)
                            HStack(spacing: Space.sm) {
                                Button("Start focusing") {
                                    withAnimation(Motion.gentle) { showsAdHocComposer = true }
                                }
                                    .buttonStyle(PrimaryButtonStyle(expands: false))
                                    .accessibilityIdentifier("anchor.focus.start-unplanned")
                                Button("Add to schedule") { showsBlockEditor = true }
                                    .buttonStyle(QuietButtonStyle(expands: false))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            #else
                            Button("Start focusing") {
                                withAnimation(Motion.gentle) { showsAdHocComposer = true }
                            }
                                .buttonStyle(PrimaryButtonStyle())
                                .accessibilityIdentifier("anchor.focus.start-unplanned")
                            Button("Add to schedule") { showsBlockEditor = true }
                                .buttonStyle(QuietButtonStyle())
                            #endif
                        }
                        .padding(Space.lg)
                        .frame(maxWidth: 980)
                        Spacer()
                    } else {
                        StartComposer(error: controller.lastError) { goal, intent, minutes, project, notes, tagIDs in
                            let started = withAnimation(Motion.gentle) {
                                controller.start(
                                    goal: goal,
                                    intent: intent,
                                    minutes: minutes,
                                    project: project,
                                    notes: notes,
                                    tagIDStrings: tagIDs
                                )
                            }
                            guard started != nil else { return false }
                            showsAdHocComposer = false
                            return true
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
                FocusPreludeStage(
                    eyebrow: block.plannedStart <= now && now < block.plannedEnd ? "Now" : (block.plannedStart > now ? "Up next" : "Still open"),
                    title: block.title,
                    message: "\(block.plannedStart.formatted(date: .omitted, time: .shortened)) · \(Format.duration(Double(block.plannedSeconds))). Everything else can wait at the edge."
                ) {
                    VStack(spacing: Space.sm) {
                        Button(isChangingActivity ? "Start actual activity" : "Start this block") {
                            start(block)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isChangingActivity && actualIntent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(isChangingActivity ? "Use the scheduled block" : "I’m doing something else") {
                            withAnimation(Motion.snappy) { isChangingActivity.toggle() }
                            actualIntent = ""
                        }
                        .buttonStyle(QuietButtonStyle())
                        Button("Start an unplanned block") {
                            withAnimation(Motion.gentle) { showsAdHocComposer = true }
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
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

                Text("Once started, Lock a distraction stays on top of the timer with quick interruption options.")
                    .font(.footnote)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(Space.lg)
            .frame(maxWidth: 980)
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
        isChangingActivity = false
        actualIntent = ""
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
private struct FocusPreludeStage<Actions: View>: View {
    @Environment(\.anchorTheme) private var theme
    private let eyebrow: String
    private let title: String
    private let message: String
    private let actions: Actions

    init(
        eyebrow: String,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontal
            vertical
        }
        .accessibilityElement(children: .contain)
    }

    private var horizontal: some View {
        HStack(alignment: .center, spacing: Space.xxl) {
            VStack(alignment: .leading, spacing: Space.lg) {
                copy(titleFont: .system(size: 40, weight: .semibold, design: .rounded))
                actions
            }
            .frame(width: 390, alignment: .leading)

            Image("FocusDoodle")
                .resizable()
                .scaledToFill()
                .frame(width: 460, height: 320)
                .clipped()
                .accessibilityHidden(true)
        }
        .frame(minWidth: 898, minHeight: 440)
        .frame(maxWidth: .infinity)
    }

    private var vertical: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            copy(titleFont: .system(.largeTitle, design: .rounded).weight(.semibold))
            artwork
                .frame(maxWidth: .infinity)
            actions
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private func copy(titleFont: Font) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(eyebrow.uppercased())
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(theme.textTertiary)
            Text(title)
                .font(titleFont)
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            DrawnUnderline(width: 82, animated: true)
            Text(message)
                .font(.body)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var artwork: some View {
        Image("FocusDoodle")
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 320)
            .accessibilityHidden(true)
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
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    // The product tour changed materially with the schedule/habit overhaul.
    // A versioned key ensures existing owners see this tour once as well.
    @AppStorage("anchor.product-tour.seen.v4") private var unifiedOnboardingSeen = false
    private let controller: FocusController
    private let storeKind: AnchorStore.StoreKind
    @Bindable private var navigation: AnchorNavigationModel
    @State private var forcedOnboardingFinished = false
    @State private var presentsOnboarding = false

    public init(
        controller: FocusController,
        storeKind: AnchorStore.StoreKind = .persistent,
        navigation: AnchorNavigationModel
    ) {
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
                SettingsScreen(storeKind: storeKind, onShowOnboarding: showOnboarding)
            } else {
                screen(for: navigation.selectedTab)
            }
        }
        .tint(theme.accent)
        #else
        TabView(selection: $navigation.selectedTab) {
            ForEach(AnchorTab.allCases) { item in
                NavigationStack {
                    screen(for: item)
                        .navigationTitle(item.label)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button { navigation.showSettings() } label: {
                                    Label("Settings", systemImage: "gearshape")
                                }
                                .accessibilityIdentifier("anchor.toolbar.settings")
                                .help("Open Settings")
                            }
                        }
                        .navigationDestination(isPresented: $navigation.showsSettings) {
                            SettingsScreen(storeKind: storeKind, onShowOnboarding: showOnboarding)
                                .navigationTitle("Settings")
                                .toolbar(.hidden, for: .tabBar)
                        }
                }
                .tabItem { Label(item.label, systemImage: item.symbolName) }
                .tag(item)
            }
        }
        .tint(theme.accent)
        #endif
        }
    }

    private var onboarding: some View {
        AnchorOnboardingView(isExistingOwnerOrientation: !sessions.isEmpty) {
            finishOnboarding(openFocus: true)
        } onOpenApp: {
            finishOnboarding(openFocus: false)
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

    private func finishOnboarding(openFocus: Bool) {
        if !shouldForceOnboarding {
            unifiedOnboardingSeen = true
        }
        forcedOnboardingFinished = true
        presentsOnboarding = false
        if openFocus { navigation.select(.focus) }
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
            case .today: TodayScreen(controller: controller) { navigation.select(.focus) }
            case .habits: HabitsScreen()
            case .history: HistoryScreen()
            }
        }
    }
}
#endif
