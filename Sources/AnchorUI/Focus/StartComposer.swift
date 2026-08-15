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

    @State private var intent: String = ""
    @State private var selectedGoalID: UUID?
    @State private var minutes: Int = 25
    @FocusState private var intentFocused: Bool

    private let onStart: (Goal?, String, Int) -> Void

    public init(onStart: @escaping (Goal?, String, Int) -> Void) {
        self.onStart = onStart
    }

    private static let presets = [15, 25, 45, 60, 90]

    private var activeGoals: [Goal] { goals.filter { !$0.isArchived } }

    private var selectedGoal: Goal? {
        activeGoals.first { $0.id == selectedGoalID }
    }

    private var canStart: Bool {
        !intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedGoal != nil
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: Space.lg) {
                header

                Card(padding: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.md) {
                        fieldLabel("What are you working on?")
                        TextField("Ship the auth flow", text: $intent, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1...3)
                            .focused($intentFocused)
                            .onSubmit(start)

                        if !activeGoals.isEmpty {
                            Divider().overlay(theme.hairline)
                            fieldLabel("Against which goal?")
                            goalPicker
                        }
                    }
                }

                Card(padding: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.md) {
                        fieldLabel("For how long?")
                        durationPicker
                    }
                }

                Button(action: start) {
                    Label("Start focusing", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canStart)
                .keyboardShortcut(.return, modifiers: .command)

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
        .background(theme.canvas)
        .onAppear {
            // Focus the field on the Mac, where a keyboard is already there and
            // typing straight away is the fastest path. On iOS the keyboard would
            // cover the duration picker and the start button before the user has
            // even seen them, so let them tap in when they're ready.
            #if os(macOS)
            intentFocused = true
            #endif
        }
    }

    private var header: some View {
        VStack(spacing: Space.xxs) {
            Image(systemName: "scope")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.accent)
            Text("Set your anchor")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
            Text("Name the work, then everything else waits.")
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
        }
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
                    withAnimation(Motion.snappy) { selectedGoalID = nil }
                } label: {
                    Chip("No goal", symbol: "circle.dashed", isSelected: selectedGoalID == nil)
                }
                .buttonStyle(.plain)

                ForEach(activeGoals) { goal in
                    Button {
                        withAnimation(Motion.snappy) { selectedGoalID = goal.id }
                    } label: {
                        Chip(
                            goal.title,
                            symbol: goal.symbolName,
                            tint: AnchorTheme.tint(goal.tintIndex),
                            isSelected: selectedGoalID == goal.id
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
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        var goal = selectedGoal

        // Typing an intention with no goal selected creates one, so the goal list
        // fills itself in from ordinary use rather than from a setup chore.
        if goal == nil, !trimmed.isEmpty {
            let created = Goal(
                title: trimmed,
                tintIndex: activeGoals.count % AnchorTheme.goalTints.count
            )
            context.insert(created)
            goal = created
        }

        onStart(goal, trimmed, minutes)
        intent = ""
        selectedGoalID = nil
    }
}
