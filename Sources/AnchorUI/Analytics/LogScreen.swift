// Mac and iPhone screens. The watch is a genuinely different shape — no
// file exporter, no pasteboard, no keyboard shortcuts — so it gets its own
// views in Watch/ rather than a pile of size guards in these.
#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

/// The parked pile, and the history behind it.
///
/// The capture sheet promises "it'll be here when you're done". This is where
/// that promise is kept — so it leads with what's still open, not with a
/// chronological dump.
public struct LogScreen: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context

    @Query(sort: \Distraction.capturedAt, order: .reverse) private var distractions: [Distraction]
    @Query(
        filter: #Predicate<FocusSession> { $0.stateRaw == "finished" },
        sort: \FocusSession.startedAt,
        order: .reverse
    ) private var sessions: [FocusSession]
    @Query(sort: \SavedTag.createdAt) private var savedTags: [SavedTag]

    @State private var tab: Tab = .open
    @State private var editingDistraction: Distraction?
    @State private var editingSession: FocusSession?

    public init() {}

    private enum Tab: String, CaseIterable, Identifiable {
        case open, all, history
        var id: String { rawValue }
        var label: String {
            switch self {
            case .open: "To deal with"
            case .all: "Everything parked"
            case .history: "Sessions"
            }
        }
    }

    private var openItems: [Distraction] { distractions.filter { !$0.isHandled } }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.xs) {
                    ForEach(Tab.allCases) { option in
                        Button {
                            withAnimation(Motion.snappy) { tab = option }
                        } label: {
                            Chip(
                                option == .open && !openItems.isEmpty
                                    ? "\(option.label) (\(openItems.count))"
                                    : option.label,
                                isSelected: tab == option
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }

                switch tab {
                case .open: parkedList(openItems, emptyIsGood: true)
                case .all: parkedList(distractions, emptyIsGood: false)
                case .history: sessionList
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(theme.canvas)
        .sheet(item: $editingDistraction) { distraction in
            DistractionEditSheet(distraction: distraction) { try? context.save() }
        }
        .sheet(item: $editingSession) { session in
            SessionEditSheet(session: session) { try? context.save() }
        }
    }

    // MARK: Parked

    @ViewBuilder
    private func parkedList(_ items: [Distraction], emptyIsGood: Bool) -> some View {
        if items.isEmpty {
            EmptyStateView(
                symbol: emptyIsGood ? "checkmark.circle" : "tray",
                title: emptyIsGood ? "Nothing waiting" : "Nothing parked yet",
                message: emptyIsGood
                    ? "Everything you parked has been dealt with."
                    : "When something pulls at you mid-session, park it and it lands here."
            )
        } else {
            Card {
                VStack(alignment: .leading, spacing: Space.sm) {
                    ForEach(items) { distraction in
                        row(distraction)
                        if distraction.id != items.last?.id {
                            Divider().overlay(theme.hairline)
                        }
                    }
                }
            }
        }
    }

    private func row(_ distraction: Distraction) -> some View {
        HStack(spacing: Space.sm) {
            Button {
                withAnimation(Motion.snappy) {
                    distraction.handledAt = distraction.isHandled ? nil : Date()
                    try? context.save()
                }
            } label: {
                Image(systemName: distraction.isHandled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(distraction.isHandled ? theme.positive : theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(distraction.isHandled ? "Mark as still open" : "Mark as handled")

            Button {
                editingDistraction = distraction
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(distraction.note)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(distraction.isHandled ? theme.textTertiary : theme.textPrimary)
                        .strikethrough(distraction.isHandled, color: theme.textTertiary)
                        .lineLimit(2)

                    HStack(spacing: Space.xxs) {
                        Text(distraction.capturedAt.formatted(.relative(presentation: .named)))
                        if let session = distraction.session, let project = session.project {
                            Text("· \(project.name)").lineLimit(1)
                        } else if let session = distraction.session, let goal = session.goal {
                            Text("· while: \(goal.title)").lineLimit(1)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)

                    tagLine(distraction.tagIDStrings)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: Space.xs)

            // Tapping the category corrects it — and a user-set category is never
            // overwritten by the model afterwards.
            Button {
                editingDistraction = distraction
            } label: {
                HStack(spacing: Space.xxs) {
                    KindGlyph(distraction.displayKind, size: 26)
                    if !distraction.kindIsUserSet, distraction.kindConfidence > 0, distraction.kindConfidence < 0.55 {
                        Image(systemName: "questionmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Change category")
        }
        .padding(.vertical, 2)
    }

    // MARK: History

    private var sessionList: some View {
        Group {
            if sessions.isEmpty {
                EmptyStateView(
                    symbol: "clock.arrow.circlepath",
                    title: "No finished sessions",
                    message: "Completed sessions show up here with what interrupted them."
                )
            } else {
                Card {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        ForEach(sessions.prefix(50)) { session in
                            sessionRow(session)
                            if session.id != sessions.prefix(50).last?.id {
                                Divider().overlay(theme.hairline)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: FocusSession) -> some View {
        Button {
            editingSession = session
        } label: {
        HStack(spacing: Space.sm) {
            let tint = session.endReason == .completed
                ? theme.positive
                : (session.endReason == .abandoned ? theme.negative : theme.textTertiary)

            Image(systemName: session.endReason == .completed
                ? "checkmark.circle.fill"
                : (session.endReason == .abandoned ? "xmark.circle.fill" : "minus.circle.fill"))
                .font(.system(size: 17))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.intent.isEmpty ? (session.goal?.title ?? "Untitled") : session.intent)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(session.endReason?.label ?? "Ended")")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                if !session.notes.isEmpty {
                    Text(session.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: Space.xxs) {
                    if let project = session.project {
                        Text(project.name)
                    }
                    tagLine(session.tagIDStrings)
                }
            }

            Spacer(minLength: Space.xs)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.duration(session.bankedSeconds))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                if session.distractionCount > 0 {
                    Text("\(session.distractionCount) interrupted")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.caution)
                }
            }
        }
        .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tagLine(_ ids: [String]) -> some View {
        let names = savedTags.filter { ids.contains($0.storageID) }.map(\.name)
        if !names.isEmpty {
            Text(names.map { "#\($0)" }.joined(separator: "  "))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
        }
    }
}

/// Edit the user's exact distraction text, explicit tags, and category lock.
struct DistractionEditSheet: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let distraction: Distraction
    let onSave: () -> Void

    @State private var note: String
    @State private var chosenKind: DistractionKind?
    @State private var tagIDs: [String]
    @State private var didChooseKind = false

    init(distraction: Distraction, onSave: @escaping () -> Void) {
        self.distraction = distraction
        self.onSave = onSave
        _note = State(initialValue: distraction.note)
        _chosenKind = State(initialValue: distraction.kind)
        _tagIDs = State(initialValue: distraction.tagIDStrings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Edit distraction")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text("Keep the words you actually used; tagging stays on-device.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }

            Card(padding: Space.md) {
                TextField("What pulled at you?", text: $note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...6)
                    .foregroundStyle(theme.textPrimary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    FlowRow(spacing: Space.xxs) {
                        ForEach(DistractionKind.allCases, id: \.self) { kind in
                            Button {
                                chosenKind = kind
                                didChooseKind = true
                            } label: {
                                Chip(
                                    kind.label,
                                    symbol: kind.symbolName,
                                    tint: theme.color(for: kind),
                                    isSelected: chosenKind == kind
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SavedTagPicker(selectedIDs: $tagIDs)
                }
            }

            HStack(spacing: Space.xs) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Space.lg)
        .frame(minWidth: 420, minHeight: 560)
        .background(theme.canvas)
    }

    private func save() {
        distraction.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        distraction.tagIDStrings = tagIDs
        if didChooseKind, let chosenKind {
            distraction.kind = chosenKind
            distraction.kindIsUserSet = true
            distraction.kindConfidence = 1
        }
        onSave()
        dismiss()
    }
}

/// A finished focus session is an entry, not a read-only statistic.
struct SessionEditSheet: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    let session: FocusSession
    let onSave: () -> Void

    @State private var intent: String
    @State private var notes: String
    @State private var projectID: UUID?
    @State private var tagIDs: [String]

    init(session: FocusSession, onSave: @escaping () -> Void) {
        self.session = session
        self.onSave = onSave
        _intent = State(initialValue: session.intent)
        _notes = State(initialValue: session.notes)
        _projectID = State(initialValue: session.project?.id)
        _tagIDs = State(initialValue: session.tagIDStrings)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("Edit focus entry")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)

                Card(padding: Space.md) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        TextField("What did you work on?", text: $intent, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .lineLimit(1...3)
                        Divider().overlay(theme.hairline)
                        TextField("Notes, context, or outcome", text: $notes, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3...8)
                            .foregroundStyle(theme.textSecondary)
                    }
                }

                ProjectPicker(selectedID: $projectID)
                SavedTagPicker(selectedIDs: $tagIDs)

                HStack(spacing: Space.xs) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Save") { save() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(Space.lg)
        }
        .frame(minWidth: 440, minHeight: 560)
        .background(theme.canvas)
    }

    private func save() {
        session.intent = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        session.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        session.project = projects.first { $0.id == projectID }
        session.tagIDStrings = tagIDs
        onSave()
        dismiss()
    }
}
#endif
