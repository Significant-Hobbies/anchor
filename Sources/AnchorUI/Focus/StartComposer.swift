// Mac and iPhone screens. The watch is a genuinely different shape — no
// file exporter, no pasteboard, no keyboard shortcuts — so it gets its own
// views in Watch/ rather than a pile of size guards in these.
#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

/// What you see when nothing is running: name the work, pick a length, go.
///
/// Deliberately one screen and three decisions. A focus app that makes you
/// configure something before you can start is a focus app you stop opening.
public struct StartComposer: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    @State private var draft = StartComposerDraft()
    @State private var minutes: Int = 25
    @State private var showsMoreContext = false
    private enum EntryField: Hashable { case intent, notes }
    @FocusState private var focusedField: EntryField?

    private let error: String?
    private let onStart: (Goal?, String, Int, Project?, String, [String]) -> Bool

    public init(error: String? = nil, onStart: @escaping (Goal?, String, Int, Project?, String, [String]) -> Bool) {
        self.error = error
        self.onStart = onStart
    }

    private static let presets = [15, 25, 45, 60, 90]

    private var activeGoals: [Goal] { goals.filter { !$0.isArchived } }

    private var selectedGoal: Goal? {
        activeGoals.first { $0.id == draft.selectedGoalID }
    }

    private var selectedProject: Project? {
        projects.first { $0.id == draft.selectedProjectID && !$0.isArchived }
    }

    private var canStart: Bool {
        !draft.intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedGoal != nil
    }

    public var body: some View {
        ScrollView {
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(theme.negative)
                    .accessibilityIdentifier("anchor.focus.start-error")
            }
            VStack(spacing: Space.lg) {
                header

                Card(padding: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.md) {
                        fieldLabel("What are you working on?")
                        TextField("Ship the auth flow", text: $draft.intent, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1...3)
                            .focused($focusedField, equals: .intent)
                            .onSubmit(start)

                        Divider().overlay(theme.hairline)
                        fieldLabel("Entry notes — optional")
                        TextField("Context, plan, or what success looks like", text: $draft.notes, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2...5)
                            .focused($focusedField, equals: .notes)

                        if !activeGoals.isEmpty {
                            Divider().overlay(theme.hairline)
                            fieldLabel("Against which goal?")
                            goalPicker
                        }

                        Divider().overlay(theme.hairline)
                        fieldLabel("For how long?")
                        durationPicker
                    }
                }

                Card(padding: Space.lg) {
                    DisclosureGroup(isExpanded: $showsMoreContext) {
                        VStack(alignment: .leading, spacing: Space.md) {
                            Divider().overlay(theme.hairline)
                            ProjectPicker(selectedID: $draft.selectedProjectID)
                            Divider().overlay(theme.hairline)
                            SavedTagPicker(selectedIDs: $draft.selectedTagIDs)
                        }
                        .padding(.top, Space.sm)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("More context")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.textPrimary)
                            Text("Project and saved tags")
                                .font(.caption)
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .tint(theme.textSecondary)
                }

                #if os(macOS)
                startButton
                #endif

                // Keyboard-shortcut hint only where there is a keyboard.
                #if os(macOS)
                Text("⌘⇧L parks a distraction without leaving your session.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                #endif
            }
            .padding(Space.lg)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            // Centre in the window rather than hugging the top, so a large Mac
            // window doesn't leave the composer stranded above a field of empty.
            .containerRelativeFrame(.vertical, alignment: .center)
        }
        .scrollDismissesKeyboard(.interactively)
        #if os(iOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focusedField == nil {
                startButton
                    .padding(.horizontal, Space.lg)
                    .padding(.top, Space.xs)
                    .padding(.bottom, Space.sm)
                    .background(theme.canvas)
            }
        }
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                #if os(iOS)
                Button("Start focusing", action: start)
                    .disabled(!canStart)
                #endif
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .background(theme.canvas)
        .onAppear {
            // Focus the field on the Mac, where a keyboard is already there and
            // typing straight away is the fastest path. On iOS the keyboard would
            // cover the duration picker and the start button before the user has
            // even seen them, so let them tap in when they're ready.
            #if os(macOS)
            focusedField = .intent
            #endif
        }
    }

    private var startButton: some View {
        Button(action: start) {
            Label("Start focusing", systemImage: "play.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canStart)
        .keyboardShortcut(.return, modifiers: .command)
    }

    private var header: some View {
        DoodleScene(
            "FocusDoodle",
            eyebrow: "Focus",
            title: "Hold one thing",
            message: "Name the work. Park what pulls you away. Return without losing the thread."
        )
        .padding(.top, Space.md)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(theme.textTertiary)
    }

    private var goalPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                Button {
                    withAnimation(Motion.snappy) { draft.selectedGoalID = nil }
                } label: {
                    Chip("No goal", symbol: "circle.dashed", isSelected: draft.selectedGoalID == nil)
                }
                .buttonStyle(.plain)

                ForEach(activeGoals) { goal in
                    Button {
                        withAnimation(Motion.snappy) { draft.selectedGoalID = goal.id }
                    } label: {
                        Chip(
                            goal.title,
                            symbol: goal.symbolName,
                            tint: AnchorTheme.tint(goal.tintIndex),
                            isSelected: draft.selectedGoalID == goal.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var durationPicker: some View {
        VStack(spacing: Space.sm) {
            HStack(spacing: Space.xs) {
                ForEach(Self.presets, id: \.self) { preset in
                    Button {
                        withAnimation(Motion.snappy) { minutes = preset }
                    } label: {
                        Text("\(preset)m")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.xs)
                            .background(
                                minutes == preset ? theme.accent.opacity(0.16) : theme.surfaceRaised,
                                in: .rect(cornerRadius: Radius.sm)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.sm)
                                    .strokeBorder(
                                        minutes == preset ? theme.accent.opacity(0.55) : theme.hairline,
                                        lineWidth: 1
                                    )
                            )
                            .foregroundStyle(minutes == preset ? theme.accent : theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: Space.sm) {
                Slider(
                    value: Binding(
                        get: { Double(minutes) },
                        set: { minutes = Int($0.rounded()) }
                    ),
                    in: 5...180,
                    step: 5
                )
                .tint(theme.accent)

                Text(Format.duration(Double(minutes) * 60))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 62, alignment: .trailing)
            }
        }
    }

    private func start() {
        guard canStart else { return }
        focusedField = nil
        _ = draft.submit(
            selectedGoal: selectedGoal, selectedProject: selectedProject,
            minutes: minutes, goalTintIndex: activeGoals.count % AnchorTheme.goalTints.count,
            context: context, onStart: onStart
        )
    }
}

/// The actual composer submission handler owns draft clearing and transient-goal cleanup.
/// Keeping the value intact on failure lets the same entry be retried.
@MainActor
struct StartComposerDraft: Equatable {
    var intent = ""
    var notes = ""
    var selectedGoalID: UUID?
    var selectedProjectID: UUID?
    var selectedTagIDs: [String] = []

    mutating func submit(
        selectedGoal: Goal?, selectedProject: Project?, minutes: Int,
        goalTintIndex: Int, context: ModelContext,
        onStart: (Goal?, String, Int, Project?, String, [String]) -> Bool
    ) -> Bool {
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || selectedGoal != nil else { return false }
        var goal = selectedGoal
        var createdGoal: Goal?
        if goal == nil, !trimmed.isEmpty {
            let created = Goal(title: trimmed, tintIndex: goalTintIndex)
            context.insert(created)
            createdGoal = created
            goal = created
        }
        guard onStart(goal, trimmed, minutes, selectedProject, notes, selectedTagIDs) else {
            if let createdGoal { context.delete(createdGoal) }
            return false
        }
        self = StartComposerDraft()
        return true
    }
}
#endif
