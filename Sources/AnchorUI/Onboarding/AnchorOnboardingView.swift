#if !os(watchOS)
import AnchorCore
import SwiftUI

public struct AnchorOnboardingView: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("anchor.onboarding.goal.v1") private var savedGoal = ""
    @AppStorage("anchor.onboarding.step.v1") private var savedStep = 0
    @State private var rehearsal = OnboardingRehearsal()
    @State private var goal = ""
    @State private var thought = ""
    @State private var minutes = 25
    @FocusState private var focusedField: Field?

    private let onStartRealSession: (String, Int) -> Void

    private enum Field: Hashable {
        case goal
        case thought
    }

    public init(onStartRealSession: @escaping (String, Int) -> Void) {
        self.onStartRealSession = onStartRealSession
    }

    public var body: some View {
        ZStack {
            theme.canvas.ignoresSafeArea()
            ScrollView {
                Group {
                    switch rehearsal.step {
                    case .goal: goalStep
                    case .focusing: focusStep
                    case .capture: captureStep
                    case .returned: returnStep
                    }
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .padding(Space.lg)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(reduceMotion ? nil : Motion.gentle, value: rehearsal.step)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["ANCHOR_ONBOARDING_DEMO"] == "1" {
                savedGoal = ""
                savedStep = 0
                goal = ""
                rehearsal = OnboardingRehearsal()
            } else {
                restore()
            }
        }
    }

    private var goalStep: some View {
        VStack(spacing: Space.lg) {
            mark
            VStack(spacing: Space.xs) {
                Text("Protect one thing.")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("Anchor keeps your goal visible, parks what pulls at you, and gives the work back.")
                    .font(.body)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Card(padding: Space.lg) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("WHAT DESERVES YOUR FOCUS?")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(theme.textTertiary)
                    TextField("Finish the release", text: $goal, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.medium))
                        .focused($focusedField, equals: .goal)
                        .lineLimit(1...3)
                    Divider().overlay(theme.hairline)
                    Label("Distraction notes stay on this device.", systemImage: "lock.shield")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Button("Try the park-and-return loop") { beginRehearsal() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(trimmedGoal.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            Text("This is a labelled rehearsal. It creates no session, history, analytics, export, or synced copy.")
                .font(.footnote)
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var focusStep: some View {
        VStack(spacing: Space.lg) {
            rehearsalLabel
            Text(rehearsal.goal)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
            FocusRing(fraction: 0.24, isRunning: true, isOpenEnded: false) {
                VStack(spacing: Space.xxs) {
                    Text("25:00").font(.title.monospacedDigit().weight(.semibold))
                    Text("PRACTICE").font(.caption2.weight(.semibold)).tracking(1.1)
                }
            }
            .frame(maxWidth: 300)
            Text("Imagine something else asks for your attention.")
                .font(.body)
                .foregroundStyle(theme.textSecondary)
            Button("Something pulled me") {
                rehearsal.openCapture()
                persist(step: .capture)
                focusedField = .thought
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut("l", modifiers: [.command, .shift])
            platformCaptureHint
        }
    }

    private var captureStep: some View {
        VStack(spacing: Space.lg) {
            rehearsalLabel
            VStack(spacing: Space.xxs) {
                Image(systemName: "lock.open.fill")
                    .font(.title2)
                    .foregroundStyle(theme.color(for: .wanderingThought))
                Text("What’s pulling at you?")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("Name it once. Then return to \(rehearsal.goal).")
                    .font(.body)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Card(padding: Space.lg) {
                TextField("Check the build status", text: $thought, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.medium))
                    .focused($focusedField, equals: .thought)
                    .lineLimit(1...4)
            }
            Label("Practice text is discarded after this screen.", systemImage: "lock.shield")
                .font(.footnote.weight(.medium))
                .foregroundStyle(theme.textSecondary)
            Button("Park it — return to focus") { parkRehearsal() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(trimmedThought.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    private var returnStep: some View {
        VStack(spacing: Space.lg) {
            rehearsalLabel
            ZStack {
                Circle().fill(theme.accent.opacity(0.14)).frame(width: 88, height: 88)
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(theme.accent)
            }
            Text("Attention recovered.")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Card(padding: Space.lg) {
                VStack(spacing: Space.xs) {
                    Text("BACK TO").font(.caption2.weight(.semibold)).tracking(1.1)
                        .foregroundStyle(theme.textTertiary)
                    Text(rehearsal.goal).font(.title3.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("The practice interruption was discarded. Your real captures stay local and appear in Parked.")
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: Space.sm) {
                Label("Apple Intelligence groups locally when available; built-in rules work without it.", systemImage: "apple.intelligence")
                Label("Optional account sync sends session totals, never distraction notes.", systemImage: "icloud")
                Label("Apple Watch is a remote for start, pause, and capture — no second setup flow.", systemImage: "applewatch")
            }
            .font(.footnote)
            .foregroundStyle(theme.textSecondary)

            VStack(spacing: Space.sm) {
                Text("START A REAL SESSION").font(.caption2.weight(.semibold)).tracking(1.1)
                    .foregroundStyle(theme.textTertiary)
                HStack(spacing: Space.xs) {
                    ForEach([15, 25, 45], id: \.self) { option in
                        Button("\(option)m") { minutes = option }
                            .buttonStyle(.bordered)
                            .tint(minutes == option ? theme.accent : theme.textTertiary)
                            .accessibilityAddTraits(minutes == option ? .isSelected : [])
                    }
                }
                Button("Begin real focus") { complete() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Practice once more") {
                    thought = ""
                    rehearsal.practiceAgain()
                    persist(step: .focusing)
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private var mark: some View {
        Image(systemName: "scope")
            .font(.system(size: 34, weight: .light))
            .foregroundStyle(theme.accent)
            .accessibilityHidden(true)
    }

    private var rehearsalLabel: some View {
        Text("REHEARSAL · NOTHING IS SAVED")
            .font(.caption2.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(theme.textTertiary)
    }

    @ViewBuilder
    private var platformCaptureHint: some View {
        #if os(macOS)
        Text("During a real session, press ⌘⇧L or use Lock a Distraction from the menu bar.")
            .font(.footnote).foregroundStyle(theme.textTertiary).multilineTextAlignment(.center)
            .accessibilityIdentifier("anchor.onboarding.platform-guidance")
        #else
        Text("During a real session, the large Lock a distraction button stays within reach.")
            .font(.footnote).foregroundStyle(theme.textTertiary).multilineTextAlignment(.center)
            .accessibilityIdentifier("anchor.onboarding.platform-guidance")
        #endif
    }

    private var trimmedGoal: String { goal.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedThought: String { thought.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func beginRehearsal() {
        guard rehearsal.begin(goal: trimmedGoal) else { return }
        savedGoal = rehearsal.goal
        persist(step: .focusing)
        focusedField = nil
    }

    private func parkRehearsal() {
        rehearsal.updateThought(thought)
        guard rehearsal.parkAndReturn() != nil else { return }
        thought = ""
        persist(step: .returned)
        focusedField = nil
    }

    private func complete() {
        savedGoal = ""
        savedStep = 0
        onStartRealSession(rehearsal.goal, minutes)
    }

    private func persist(step: OnboardingRehearsal.Step) {
        savedStep = step.rawValue
    }

    private func restore() {
        goal = savedGoal
        guard !savedGoal.isEmpty,
              let step = OnboardingRehearsal.Step(rawValue: savedStep),
              step != .goal else { return }
        var restored = OnboardingRehearsal()
        guard restored.begin(goal: savedGoal) else { return }
        if step == .capture { restored.openCapture() }
        if step == .returned {
            restored.openCapture()
            restored.updateThought("Recovered practice thought")
            _ = restored.parkAndReturn()
        }
        rehearsal = restored
    }
}

public struct AnchorExistingOwnerOrientationView: View {
    @Environment(\.anchorTheme) private var theme
    private let onContinue: () -> Void

    public init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: Space.lg) {
            Image(systemName: "scope").font(.largeTitle).foregroundStyle(theme.accent)
            Text("Anchor is ready here.")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Your existing sessions take precedence. The same focus, pause, and park controls are available on this device.")
                .font(.body).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
            #if os(macOS)
            Text("Press ⌘⇧L to park a distraction. The menu bar keeps the timer reachable.")
                .font(.footnote).foregroundStyle(theme.textTertiary).multilineTextAlignment(.center)
            #else
            Text("Tap Lock a distraction during a session. A paired Watch acts as a remote.")
                .font(.footnote).foregroundStyle(theme.textTertiary).multilineTextAlignment(.center)
            #endif
            Button("Continue") { onContinue() }.buttonStyle(PrimaryButtonStyle())
        }
        .padding(Space.xl)
        .frame(maxWidth: 560, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .background(theme.canvas)
    }
}
#endif
