#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

public struct AnchorOnboardingView: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var context
    @Query private var profiles: [BehaviorProfile]
    @AppStorage("anchor.onboarding.unified-step.v1") private var savedUnifiedStep = 0
    @AppStorage("anchor.onboarding.goal.v1") private var savedGoal = ""
    @AppStorage("anchor.onboarding.step.v1") private var savedStep = 0
    @State private var unifiedStep: UnifiedStep = .welcome
    @State private var selectedPatterns: Set<BehaviorPattern> = []
    @State private var desiredDirections: Set<LifeDirection> = []
    @State private var rehearsal = OnboardingRehearsal()
    @State private var goal = ""
    @State private var thought = ""
    @State private var minutes = 25
    @State private var profileSaveError: String?
    @FocusState private var focusedField: Field?

    private let isExistingOwnerOrientation: Bool
    private let onStartRealSession: (String, Int) -> Void
    private let onOpenApp: () -> Void

    private enum Field: Hashable {
        case goal
        case thought
    }

    private enum UnifiedStep: Int, CaseIterable {
        case welcome
        case patterns
        case directions
        case rehearsal
    }

    public init(
        isExistingOwnerOrientation: Bool = false,
        onStartRealSession: @escaping (String, Int) -> Void,
        onOpenApp: @escaping () -> Void = {}
    ) {
        self.isExistingOwnerOrientation = isExistingOwnerOrientation
        self.onStartRealSession = onStartRealSession
        self.onOpenApp = onOpenApp
    }

    public var body: some View {
        ZStack {
            theme.canvas.ignoresSafeArea()
            ScrollView {
                Group {
                    switch unifiedStep {
                    case .welcome: mergedWelcomeStep
                    case .patterns: patternsStep
                    case .directions: directionsStep
                    case .rehearsal:
                        switch rehearsal.step {
                        case .goal: goalStep
                        case .focusing: focusStep
                        case .capture: captureStep
                        case .returned: returnStep
                        }
                    }
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .padding(Space.lg)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(reduceMotion ? nil : Motion.gentle, value: unifiedStep)
        .animation(reduceMotion ? nil : Motion.gentle, value: rehearsal.step)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["ANCHOR_ONBOARDING_DEMO"] == "1" {
                savedUnifiedStep = 0
                savedGoal = ""
                savedStep = 0
                unifiedStep = .welcome
                goal = ""
                rehearsal = OnboardingRehearsal()
            } else {
                restoreProfile()
                unifiedStep = UnifiedStep(rawValue: savedUnifiedStep) ?? .welcome
                restore()
            }
        }
    }

    private var mergedWelcomeStep: some View {
        VStack(spacing: Space.lg) {
            Image("HabitsOnboarding")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 260)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("A person balances time that slips away against time deliberately chosen for movement and growth.")

            VStack(spacing: Space.xs) {
                Text("Plan the day. Learn what moved it.")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Anchor compares the day you meant to live with the one you actually lived — without treating every change as failure.")
                    .font(.body)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Card(padding: Space.lg) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    mergedPromise("Build a realistic schedule", symbol: "calendar")
                    mergedPromise("Catch interruptions while they happen", symbol: "bell.badge")
                    mergedPromise("Separate your choices from what came to you", symbol: "arrow.triangle.branch")
                }
            }

            Button("Choose what to protect") { moveUnified(to: .patterns) }
                .buttonStyle(PrimaryButtonStyle())
            Button(isExistingOwnerOrientation ? "Return to Anchor" : "I’ll explore first") { onOpenApp() }
                .buttonStyle(QuietButtonStyle())
            Text("About two minutes · everything is editable later")
                .font(.footnote)
                .foregroundStyle(theme.textTertiary)
        }
    }

    private var patternsStep: some View {
        VStack(spacing: Space.lg) {
            onboardingProgress("1 OF 3 · OPTIONAL")
            VStack(spacing: Space.xs) {
                Text("What tends to take more time than you want?")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Choose anything you still enjoy but sometimes do on automatic. Anchor will never call intentional time a failure.")
                    .font(.body)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138, maximum: 190), spacing: Space.sm)], spacing: Space.sm) {
                ForEach(BehaviorPattern.allCases, id: \.self) { pattern in
                    BehavioralArtworkTile(
                        imageName: pattern.artworkName,
                        title: pattern.label,
                        isSelected: selectedPatterns.contains(pattern)
                    ) {
                        if selectedPatterns.contains(pattern) {
                            selectedPatterns.remove(pattern)
                        } else {
                            selectedPatterns.insert(pattern)
                        }
                        persistProfile()
                    }
                }
            }

            VStack(spacing: Space.sm) {
                profileSaveFailure
                Button(selectedPatterns.isEmpty ? "Continue without choosing" : "Continue with \(selectedPatterns.count) selected") {
                    if persistProfile() { moveUnified(to: .directions) }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Back") { moveUnified(to: .welcome) }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private var directionsStep: some View {
        VStack(spacing: Space.lg) {
            onboardingProgress("2 OF 3 · OPTIONAL")
            VStack(spacing: Space.xs) {
                Text("What do you want that time to make room for?")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("These are directions, not prescriptions. Anchor will use only the ones you choose when a replacement could genuinely help.")
                    .font(.body)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: Space.sm)], spacing: Space.sm) {
                ForEach(LifeDirection.allCases, id: \.self) { direction in
                    BehavioralArtworkTile(
                        imageName: direction.artworkName,
                        title: direction.label,
                        isSelected: desiredDirections.contains(direction)
                    ) {
                        if desiredDirections.contains(direction) {
                            desiredDirections.remove(direction)
                        } else {
                            desiredDirections.insert(direction)
                        }
                        persistProfile()
                    }
                }
            }

            VStack(spacing: Space.sm) {
                profileSaveFailure
                Button(desiredDirections.isEmpty ? "Continue without choosing" : "Show me how Anchor protects it") {
                    if persistProfile() { moveUnified(to: .rehearsal) }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Back") { moveUnified(to: .patterns) }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private var goalStep: some View {
        VStack(spacing: Space.lg) {
            onboardingProgress("3 OF 3 · QUICK REHEARSAL")
            Image("AnchorOnboarding")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("A hand-drawn figure anchors a focus clock and parks a ringing interruption.")
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
            Button(isExistingOwnerOrientation ? "Return to Anchor" : "Open Anchor first") { onOpenApp() }
                .buttonStyle(QuietButtonStyle())
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
            Button("Leave rehearsal") { onOpenApp() }
                .buttonStyle(QuietButtonStyle())
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
            Button("Leave rehearsal") { onOpenApp() }
                .buttonStyle(QuietButtonStyle())
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
            Text("Thought parked.")
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
                Label("iCloud keeps your Anchor data available on your Mac, iPhone, and Apple Watch.", systemImage: "icloud")
                Label("Significant Hobbies Hub is optional and receives only finished session summaries — never distraction notes.", systemImage: "person.crop.circle.badge.checkmark")
                Label("Apple Watch is a remote for start, pause, and capture — no second setup flow.", systemImage: "applewatch")
            }
            .font(.footnote)
            .foregroundStyle(theme.textSecondary)

            VStack(spacing: Space.sm) {
                profileSaveFailure
                Text("START A REAL SESSION").font(.caption2.weight(.semibold)).tracking(1.1)
                    .foregroundStyle(theme.textTertiary)
                HStack(spacing: Space.xs) {
                    ForEach([15, 25, 45], id: \.self) { option in
                        Button("\(option)m") { minutes = option }
                            .buttonStyle(.bordered)
                            .frame(minWidth: 44, minHeight: 44)
                            .tint(minutes == option ? theme.accent : theme.textTertiary)
                            .accessibilityAddTraits(minutes == option ? .isSelected : [])
                    }
                }
                Button("Begin real focus") { complete() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                Button(isExistingOwnerOrientation ? "Return without starting" : "Open Anchor without starting") { onOpenApp() }
                    .buttonStyle(QuietButtonStyle())
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

    private func mergedPromise(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.body.weight(.medium))
            .foregroundStyle(theme.textSecondary)
    }

    private func onboardingProgress(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(theme.textTertiary)
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
        guard persistProfile() else { return }
        savedUnifiedStep = 0
        savedGoal = ""
        savedStep = 0
        onStartRealSession(rehearsal.goal, minutes)
    }

    private func moveUnified(to step: UnifiedStep) {
        focusedField = nil
        savedUnifiedStep = step.rawValue
        withAnimation(reduceMotion ? .easeInOut(duration: 0.16) : Motion.gentle) {
            unifiedStep = step
        }
    }

    private func restoreProfile() {
        guard let profile = profiles.first else { return }
        selectedPatterns = profile.selectedPatterns
        desiredDirections = profile.desiredDirections
    }

    @discardableResult
    private func persistProfile() -> Bool {
        do {
            let profile: BehaviorProfile
            if let existing = try context.fetch(FetchDescriptor<BehaviorProfile>()).first {
                profile = existing
            } else {
                profile = BehaviorProfile()
                context.insert(profile)
            }
            profile.selectedPatterns = selectedPatterns
            profile.desiredDirections = desiredDirections
            profile.updatedAt = Date()
            try context.save()
            profileSaveError = nil
            return true
        } catch {
            context.rollback()
            profileSaveError = "Anchor couldn’t save these choices. They’re still selected here; try again."
            return false
        }
    }

    @ViewBuilder
    private var profileSaveFailure: some View {
        if let profileSaveError {
            Label(profileSaveError, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(theme.negative)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("anchor.onboarding.profile-save-error")
        }
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

struct BehavioralArtworkTile: View {
    @Environment(\.anchorTheme) private var theme
    let imageName: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.xs) {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 112)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityHidden(true)
                HStack(spacing: Space.xxs) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? theme.accent : theme.textTertiary)
                }
                .padding(.horizontal, Space.sm)
                .padding(.bottom, Space.sm)
            }
            .background(theme.surface, in: .rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(isSelected ? theme.accent : theme.hairline, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#endif
