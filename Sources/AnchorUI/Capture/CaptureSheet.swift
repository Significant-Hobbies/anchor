// Mac and iPhone screens. The watch is a genuinely different shape — no
// file exporter, no pasteboard, no keyboard shortcuts — so it gets its own
// views in Watch/ rather than a pile of size guards in these.
#if !os(watchOS)
import AnchorCore
import SwiftUI

/// The lock.
///
/// Something is pulling at you. This takes the thought out of your head in one
/// sentence, puts it somewhere you trust, and hands you back the number you were
/// working against. The confirmation exists on purpose: the point is not to file
/// a record, it's to feel the redirection.
public struct CaptureSheet: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private let controller: FocusController

    @State private var note: String = ""
    @State private var chosenKind: DistractionKind?
    @State private var selectedTagIDs: [String] = []
    @State private var parked: Parked?
    @FocusState private var fieldFocused: Bool

    public init(controller: FocusController) {
        self.controller = controller
    }

    private struct Parked: Equatable {
        var note: String
        var goal: String
        var remaining: Double
        var isOpenEnded: Bool
    }

    /// The categories worth one tap. The rest are inferred on-device, and any of
    /// them can be corrected later from the log.
    private static let quickKinds: [DistractionKind] = [
        .message, .notification, .person, .wanderingThought, .rabbitHole, .socialFeed, .otherWork,
    ]

    private var canPark: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        ZStack {
            theme.canvas.ignoresSafeArea()
            if let parked {
                confirmation(parked)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            } else {
                composer
                    .transition(.opacity)
            }
        }
        .animation(Motion.snappy, value: parked)
        .frame(minWidth: 380, minHeight: 420)
    }

    // MARK: Composer

    /// Coming back from a pause is a different question from reaching for the lock
    /// button mid-flow: one is "what pulled you away", the other "what's pulling".
    private var isReturningFromPause: Bool {
        if case .returnedFromPause = controller.captureReason { return true }
        return false
    }

    private var awaySeconds: Double? {
        if case .returnedFromPause(let seconds) = controller.captureReason { return seconds }
        return nil
    }

    private var composer: some View {
        ScrollView {
        VStack(spacing: Space.lg) {
            VStack(spacing: Space.xxs) {
                Image(systemName: isReturningFromPause ? "arrow.uturn.left.circle" : "lock.open.fill")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(theme.accent)
                Text(isReturningFromPause ? "Welcome back. What pulled you away?" : "What's pulling at you?")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                if let awaySeconds, awaySeconds >= 5 {
                    Text("You were away \(Format.duration(awaySeconds)).")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    Text("Name it once. It'll be here when you're done.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                }
            }

            Card(padding: Space.md) {
                VStack(alignment: .trailing, spacing: Space.xs) {
                    TextField(
                        isReturningFromPause ? "Ravi came over about the invoice" : "Slack from Ravi about the invoice",
                        text: $note,
                        axis: .vertical
                    )
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1...4)
                        .focused($fieldFocused)
                        .onSubmit(park)
                    if fieldFocused {
                        Button("Done") { fieldFocused = false }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.accent)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Category — optional, otherwise it's tagged on-device")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(theme.textTertiary)

                FlowRow(spacing: Space.xxs) {
                    ForEach(Self.quickKinds, id: \.self) { kind in
                        Button {
                            withAnimation(Motion.snappy) {
                                chosenKind = chosenKind == kind ? nil : kind
                            }
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
            }

            SavedTagPicker(selectedIDs: $selectedTagIDs)

            Spacer(minLength: 0)

            VStack(spacing: Space.xs) {
                Button(action: park) {
                    Label(
                        isReturningFromPause ? "Log it — back to work" : "Park it — back to work",
                        systemImage: "arrow.uturn.backward"
                    )
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canPark)
                .keyboardShortcut(.return, modifiers: [])

                if !isReturningFromPause {
                    Button(action: surrender) {
                        Text("It wins — end the session")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(!canPark)
                }

                // Asking on every resume only works if saying "nothing" is
                // instant. Escape does the same thing.
                Button(isReturningFromPause ? "Nothing — just a break" : "Cancel") {
                    controller.dismissCapture()
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Space.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldFocused = false }
            }
        }
        .onAppear { fieldFocused = true }
    }

    // MARK: Confirmation

    private func confirmation(_ parked: Parked) -> some View {
        VStack(spacing: Space.md) {
            ZStack {
                Circle()
                    .fill(theme.accent.opacity(0.14))
                    .frame(width: 78, height: 78)
                Image(systemName: "lock.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(theme.accent)
            }

            Text("Parked.")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)

            Text("“\(parked.note)”")
                .font(.system(size: 14))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, Space.md)

            Card(padding: Space.md) {
                VStack(spacing: Space.xxs) {
                    Text("BACK TO")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(theme.textTertiary)
                    Text(parked.goal)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if !parked.isOpenEnded {
                        Text("\(Format.clock(parked.remaining)) remaining")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(theme.accent)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Button("Back to work") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding(Space.lg)
        .task {
            // Long enough to read the three lines, short enough not to be in the way.
            try? await Task.sleep(for: .milliseconds(2000))
            dismiss()
        }
    }

    // MARK: Actions

    private func park() {
        guard canPark else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = controller.session
        controller.park(note: trimmed, kind: chosenKind, tagIDStrings: selectedTagIDs)
        parked = Parked(
            note: trimmed,
            goal: session?.intent.isEmpty == false
                ? session!.intent
                : (session?.goal?.title ?? "your work"),
            remaining: controller.remaining,
            isOpenEnded: session?.account.isOpenEnded ?? false
        )
    }

    private func surrender() {
        guard canPark else { return }
        controller.surrender(
            to: note.trimmingCharacters(in: .whitespacesAndNewlines),
            tagIDStrings: selectedTagIDs
        )
        dismiss()
    }
}
#endif
