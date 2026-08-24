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
    @State private var habitDrafts: [HabitDraft] = []
    @State private var rehearsal = OnboardingRehearsal()
    @State private var goal = ""
    @State private var thought = ""
    @State private var profileSaveError: String?
    @FocusState private var focusedField: Field?

    private let isExistingOwnerOrientation: Bool
    private let onComplete: () -> Void
    private let onOpenApp: () -> Void

    private enum Field: Hashable {
        case goal
        case thought
    }

    private enum UnifiedStep: Int, CaseIterable {
        case welcome
        case patterns
        case directions
        case replacements
        case schedule
        case rehearsal
    }

    private struct HabitDraft: Identifiable {
        var direction: LifeDirection
        var pattern: BehaviorPattern?
        var title: String
        var time: Date
        var minutes: Int
        var weekdays: Set<ScheduleWeekday>
        var flexibility: ScheduleFlexibility
        var isSelected: Bool

        var id: LifeDirection { direction }
    }

    public init(
        isExistingOwnerOrientation: Bool = false,
        onComplete: @escaping () -> Void,
        onOpenApp: @escaping () -> Void = {}
    ) {
        self.isExistingOwnerOrientation = isExistingOwnerOrientation
        self.onComplete = onComplete
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
                    case .replacements: replacementsStep
                    case .schedule: scheduleStep
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
            onboardingProgress("1 OF 5 · OPTIONAL")
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
            onboardingProgress("2 OF 5 · OPTIONAL")
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
                    if persistProfile() {
                        prepareHabitDrafts()
                        moveUnified(to: .replacements)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Back") { moveUnified(to: .patterns) }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private var replacementsStep: some View {
        VStack(spacing: Space.lg) {
            onboardingProgress("3 OF 5 · SUGGESTIONS")
            VStack(spacing: Space.xs) {
                Text("Turn that time into something concrete.")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Anchor suggests a small replacement for every direction you chose. Keep, edit, or skip each one — these are starting points, not prescriptions.")
                    .font(.body)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if habitDrafts.isEmpty {
                EmptyStateView(
                    symbol: "sparkles",
                    title: "No replacements selected",
                    message: "That’s fine. You can create habits later, and still use Anchor for your schedule and interruptions."
                )
            } else {
                VStack(spacing: Space.sm) {
                    ForEach($habitDrafts) { $draft in
                        Button { draft.isSelected.toggle() } label: {
                            Card(padding: Space.md) {
                                HStack(spacing: Space.md) {
                                    Image(draft.direction.artworkName)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 86, height: 72)
                                        .clipShape(.rect(cornerRadius: Radius.md))
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(draft.title)
                                            .font(.headline)
                                            .foregroundStyle(theme.textPrimary)
                                        Text("For \(draft.direction.label.lowercased())")
                                            .font(.subheadline)
                                            .foregroundStyle(theme.textSecondary)
                                        if let pattern = draft.pattern {
                                            Text("Instead of defaulting to \(pattern.label.lowercased())")
                                                .font(.caption)
                                                .foregroundStyle(theme.textTertiary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: draft.isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(draft.isSelected ? theme.accent : theme.textTertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(draft.isSelected ? "Selected" : "Not selected")
                    }
                }
            }

            VStack(spacing: Space.sm) {
                Button(habitDrafts.contains(where: \.isSelected) ? "Schedule these habits" : "Continue without habits") {
                    moveUnified(to: .schedule)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Back") { moveUnified(to: .directions) }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private var scheduleStep: some View {
        VStack(spacing: Space.lg) {
            onboardingProgress("4 OF 5 · YOUR WEEK")
            VStack(spacing: Space.xs) {
                Text("Give each habit a real place.")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("These recurring blocks will appear in Today, and Focus will automatically put the right one in front of you.")
                    .font(.body)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            ForEach($habitDrafts) { $draft in
                if draft.isSelected {
                    Card(padding: Space.lg) {
                        VStack(alignment: .leading, spacing: Space.md) {
                            HStack {
                                Image(systemName: draft.direction.symbolName)
                                    .foregroundStyle(theme.accent)
                                TextField("Habit name", text: $draft.title)
                                    .font(.headline)
                            }
                            DatePicker("Starts", selection: $draft.time, displayedComponents: .hourAndMinute)
                            Stepper("\(draft.minutes) minutes", value: $draft.minutes, in: 5...120, step: 5)
                            Picker("Flexibility", selection: $draft.flexibility) {
                                ForEach(ScheduleFlexibility.allCases, id: \.self) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text("Repeats")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(theme.textTertiary)
                                HStack(spacing: Space.xxs) {
                                    ForEach(ScheduleWeekday.allCases, id: \.self) { day in
                                        Button {
                                            if draft.weekdays.contains(day) {
                                                draft.weekdays.remove(day)
                                            } else {
                                                draft.weekdays.insert(day)
                                            }
                                        } label: {
                                            Text(day.shortLabel)
                                                .frame(minWidth: 32, minHeight: 32)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(draft.weekdays.contains(day) ? theme.accent : theme.textTertiary)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if !habitDrafts.contains(where: \.isSelected) {
                EmptyStateView(
                    symbol: "calendar",
                    title: "Start with your own schedule",
                    message: "You can add one-off blocks in Today and recurring habits from Habits."
                )
            }

            VStack(spacing: Space.sm) {
                profileSaveFailure
                Button("Save schedule and learn interruptions") {
                    if persistHabitSchedule() { moveUnified(to: .rehearsal) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(habitDrafts.contains { $0.isSelected && ($0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.weekdays.isEmpty) })
                Button("Back") { moveUnified(to: .replacements) }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private var goalStep: some View {
        VStack(spacing: Space.lg) {
            onboardingProgress("5 OF 5 · QUICK REHEARSAL")
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
                    Text("The practice interruption was discarded. Your real captures stay local and appear in History.")
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
                Text("YOUR SCHEDULE IS READY").font(.caption2.weight(.semibold)).tracking(1.1)
                    .foregroundStyle(theme.textTertiary)
                Text("Focus will now choose the current or next item from that schedule. You can always tell it when reality changed.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Open my Focus") { complete() }
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
        onComplete()
    }

    private func prepareHabitDrafts() {
        let existing = Dictionary(uniqueKeysWithValues: habitDrafts.map { ($0.direction, $0) })
        let patterns = BehaviorPattern.allCases.filter { selectedPatterns.contains($0) }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        habitDrafts = LifeDirection.allCases
            .filter { desiredDirections.contains($0) }
            .enumerated()
            .map { index, direction in
                if let draft = existing[direction] { return draft }
                let suggestion = direction.habitSuggestion
                return HabitDraft(
                    direction: direction,
                    pattern: patterns.isEmpty ? nil : patterns[index % patterns.count],
                    title: suggestion.title,
                    time: Calendar.current.date(byAdding: .minute, value: suggestion.startMinutesFromMidnight, to: startOfDay) ?? startOfDay,
                    minutes: suggestion.plannedMinutes,
                    weekdays: Set(ScheduleWeekday.allCases),
                    flexibility: .flexible,
                    isSelected: true
                )
            }
    }

    private func persistHabitSchedule() -> Bool {
        guard persistProfile() else { return false }
        do {
            let existing = try context.fetch(FetchDescriptor<ScheduleTemplate>())
            let calendar = Calendar.current
            for draft in habitDrafts where draft.isSelected {
                let template: ScheduleTemplate
                if let saved = existing.first(where: { !$0.isArchived && $0.lifeDirection == draft.direction }) {
                    template = saved
                } else {
                    template = ScheduleTemplate(
                        title: draft.title,
                        startMinutesFromMidnight: 0,
                        plannedSeconds: draft.minutes * 60,
                        kind: .routine
                    )
                    context.insert(template)
                }
                template.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                template.startMinutesFromMidnight = calendar.component(.hour, from: draft.time) * 60
                    + calendar.component(.minute, from: draft.time)
                template.plannedSeconds = draft.minutes * 60
                template.weekdays = draft.weekdays
                template.kind = .routine
                template.flexibility = draft.flexibility
                template.behaviorPattern = draft.pattern
                template.lifeDirection = draft.direction
            }
            try context.save()
            _ = try DayPlanService(context: context).materialize(day: Date())
            profileSaveError = nil
            return true
        } catch {
            context.rollback()
            profileSaveError = "Anchor couldn’t save this schedule. Your choices are still here; try again."
            return false
        }
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
