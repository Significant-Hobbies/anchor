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
    private let controller: FocusController

    public init(controller: FocusController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            theme.canvas.ignoresSafeArea()
            if controller.hasSession {
                RunningSessionView(controller: controller)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.gentle, value: controller.hasSession)
        .sheet(isPresented: Binding(
            get: { controller.isCapturing },
            set: { controller.isCapturing = $0 }
        )) {
            CaptureSheet(controller: controller)
                .anchorTheme()
        }
    }
}

/// Tabs, shared by both platforms so the two apps stay conceptually identical.
public enum AnchorTab: String, CaseIterable, Identifiable, Sendable {
    case focus, log, insights, settings

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .focus: "Focus"
        case .log: "Parked"
        case .insights: "Insights"
        case .settings: "Settings"
        }
    }

    public var symbolName: String {
        switch self {
        case .focus: "scope"
        case .log: "tray.full"
        case .insights: "chart.bar.xaxis"
        case .settings: "gearshape"
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
    @AppStorage("anchor.onboarding.completed.v1") private var onboardingCompleted = false
    private let controller: FocusController
    @State private var tab: AnchorTab = .focus

    public init(controller: FocusController) {
        self.controller = controller
        _tab = State(
            initialValue: DemoData.initialTab.flatMap(AnchorTab.init(rawValue:)) ?? .focus
        )
    }

    public var body: some View {
        Group {
            if controller.hasSession || shouldSkipOnboarding {
                appShell
            } else if shouldForceOnboarding || (!onboardingCompleted && sessions.isEmpty) {
                AnchorOnboardingView { goal, minutes in
                    onboardingCompleted = true
                    _ = controller.start(goal: nil, intent: goal, minutes: minutes)
                }
            } else if onboardingCompleted {
                appShell
            } else {
                AnchorExistingOwnerOrientationView {
                    onboardingCompleted = true
                }
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
                screen(for: item)
                    .tabItem { Label(item.label, systemImage: item.symbolName) }
                    .tag(item)
            }
        }
        .tint(theme.accent)
        #endif
    }

    private var shouldForceOnboarding: Bool {
        ProcessInfo.processInfo.environment["ANCHOR_ONBOARDING_DEMO"] == "1"
    }

    private var shouldSkipOnboarding: Bool {
        ProcessInfo.processInfo.environment["ANCHOR_ONBOARDING_SKIP"] == "1"
    }

    @ViewBuilder
    private func screen(for tab: AnchorTab) -> some View {
        switch tab {
        case .focus: FocusScreen(controller: controller)
        case .log: LogScreen()
        case .insights: AnalyticsScreen()
        case .settings: SettingsScreen()
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
