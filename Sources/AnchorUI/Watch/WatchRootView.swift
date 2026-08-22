#if os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

/// Anchor on the wrist.
///
/// The watch is a **remote**, not a smaller copy of the app: it starts, pauses,
/// resumes and captures, and it never tries to show analytics. Apple ships no
/// on-device language model for watchOS, so anything captured here is tagged by
/// rules and re-tagged properly by the phone or Mac once CloudKit syncs it.
///
/// Its real job is the one thing a wrist is better at than a laptop: catching
/// the interruption at the moment it happens, without you picking anything up.
public struct WatchRootView: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    private let controller: FocusController

    public init(controller: FocusController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            theme.canvas.ignoresSafeArea()
            if controller.isCapturing {
                WatchCaptureView(controller: controller)
            } else if controller.hasSession {
                WatchSessionView(controller: controller)
            } else {
                WatchStartView(controller: controller)
            }
        }
        .animation(Motion.snappy, value: controller.hasSession)
        .animation(Motion.snappy, value: controller.isCapturing)
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
}

// MARK: - Running

struct WatchSessionView: View {
    @Environment(\.anchorTheme) private var theme
    let controller: FocusController

    private var displaySeconds: Double {
        controller.session?.account.isOpenEnded == true ? controller.elapsed : controller.remaining
    }

    private var headline: String {
        let session = controller.session
        if let intent = session?.intent, !intent.isEmpty { return intent }
        return session?.goal?.title ?? "Focusing"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xs) {
                Text(headline)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                ZStack {
                    FocusRing(
                        fraction: controller.fraction,
                        isRunning: controller.isRunning,
                        isOpenEnded: controller.session?.account.isOpenEnded ?? false
                    ) {
                        VStack(spacing: 0) {
                            Text(Format.clock(displaySeconds))
                                .font(.system(size: 30, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(theme.textPrimary)
                                .contentTransition(.numericText(countsDown: true))
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            Text(controller.isPaused ? "PAUSED" : "LEFT")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(theme.textTertiary)
                        }
                        .padding(.horizontal, Space.sm)
                    }
                }
                .frame(height: 132)

                // The wrist's whole advantage: catching the interruption
                // without picking anything up.
                Button {
                    controller.beginManualCapture()
                } label: {
                    Label("Lock", systemImage: "lock.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    controller.isPaused ? controller.resume() : controller.pause()
                } label: {
                    Label(
                        controller.isPaused ? "Resume" : "Pause",
                        systemImage: controller.isPaused ? "play.fill" : "pause.fill"
                    )
                }
                .buttonStyle(QuietButtonStyle())

                Button {
                    controller.end(reason: .endedEarly)
                } label: {
                    Label("End", systemImage: "stop.fill")
                }
                .buttonStyle(QuietButtonStyle())

                if !controller.parked.isEmpty {
                    Text("\(controller.parked.count) parked")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.top, Space.xxs)
                }
            }
            .padding(.horizontal, Space.xs)
        }
    }
}

// MARK: - Start

struct WatchStartView: View {
    @Environment(\.anchorTheme) private var theme
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]

    let controller: FocusController

    @State private var minutes: Double = 25

    private var activeGoals: [Goal] { goals.filter { !$0.isArchived } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Set your anchor")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)

                // The Digital Crown is the only good input on a watch, so the
                // duration is bound to it rather than to a row of tiny buttons.
                HStack {
                    Text("\(Int(minutes))m")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.accent)
                    Spacer()
                    Image(systemName: "digitalcrown.arrow.clockwise.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(.vertical, Space.xxs)
                .focusable()
                .digitalCrownRotation(
                    $minutes,
                    from: 5,
                    through: 180,
                    by: 5,
                    sensitivity: .low,
                    isContinuous: false
                )

                if activeGoals.isEmpty {
                    Text("Start a session on your phone or Mac first — its goals show up here.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    Text("PICK UP")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(theme.textTertiary)

                    ForEach(activeGoals.prefix(6)) { goal in
                        Button {
                            controller.start(goal: goal, intent: goal.title, minutes: Int(minutes))
                        } label: {
                            HStack(spacing: Space.xs) {
                                Image(systemName: goal.symbolName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AnchorTheme.tint(goal.tintIndex))
                                Text(goal.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(theme.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, Space.xxs)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Space.xs)
        }
    }
}

// MARK: - Capture

/// Capture on a watch is mostly one tap.
///
/// Typing is not realistic here, so the categories *are* the input: tapping one
/// records it immediately, using the category name as the note. Dictation is
/// offered for when the specific thing matters ("Ravi about the invoice"), but it
/// is never the fast path.
struct WatchCaptureView: View {
    @Environment(\.anchorTheme) private var theme
    let controller: FocusController

    @State private var note = ""

    private var isReturningFromPause: Bool {
        if case .returnedFromPause = controller.captureReason { return true }
        return false
    }

    private static let quickKinds: [DistractionKind] = [
        .message, .person, .notification, .wanderingThought, .otherWork, .socialFeed,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(isReturningFromPause ? "What pulled you away?" : "What's pulling at you?")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.leading)

                TextField("Dictate…", text: $note)
                    .font(.system(size: 13))
                    .onSubmit(saveTyped)

                if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(isReturningFromPause ? "Log it" : "Park it", action: saveTyped)
                        .buttonStyle(PrimaryButtonStyle())
                }

                ForEach(Self.quickKinds, id: \.self) { kind in
                    Button {
                        controller.park(note: kind.label, kind: kind)
                        controller.dismissCapture()
                    } label: {
                        HStack(spacing: Space.xs) {
                            KindGlyph(kind, size: 24)
                            Text(kind.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }

                Button(isReturningFromPause ? "Just a break" : "Cancel") {
                    controller.dismissCapture()
                }
                .buttonStyle(QuietButtonStyle())
                .padding(.top, Space.xxs)
            }
            .padding(.horizontal, Space.xs)
        }
    }

    private func saveTyped() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        controller.park(note: trimmed)
        note = ""
        controller.dismissCapture()
    }
}
#endif
