// Mac and iPhone screens. The watch is a genuinely different shape — no
// file exporter, no pasteboard, no keyboard shortcuts — so it gets its own
// views in Watch/ rather than a pile of size guards in these.
#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

/// Anchor, shrunk to fit the menu bar.
///
/// This is not a status readout with a link to "open the real app" — it is the
/// app, small. You can start a session, pause it, resume it (which asks what
/// pulled you away), park a distraction and end, without the main window ever
/// coming forward. That matters because the whole product is about not breaking
/// out of what you were doing.
public struct CompactPanel: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]
    @Query(sort: \PlanBlock.plannedStart) private var blocks: [PlanBlock]

    private let controller: FocusController
    private let onOpenWindow: () -> Void
    private let onQuit: (() -> Void)?

    @State private var intent = ""
    @State private var minutes = 25
    @State private var quickNote = ""
    @State private var now = Date()
    @State private var showsAdHocComposer = false
    @State private var startError: String?
    @FocusState private var intentFocused: Bool
    @FocusState private var noteFocused: Bool

    public init(
        controller: FocusController,
        onOpenWindow: @escaping () -> Void,
        onQuit: (() -> Void)? = nil
    ) {
        self.controller = controller
        self.onOpenWindow = onOpenWindow
        self.onQuit = onQuit
    }

    private static let presets = [15, 25, 45, 60]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.sm) {
                if controller.isCapturing {
                    CompactCapture(controller: controller)
                } else if controller.hasSession {
                    running
                } else {
                    idle
                }

                Divider().overlay(theme.hairline)
                footer
            }
            .padding(Space.md)
        }
        .frame(width: 300)
        .frame(maxHeight: 520)
        .scrollBounceBehavior(.basedOnSize)
        .background(theme.canvas)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
    }

    // MARK: Running

    private var running: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .center, spacing: Space.sm) {
                // The same ring as the main window, just small. One idea, two sizes.
                FocusRing(
                    fraction: controller.fraction,
                    isRunning: controller.isRunning,
                    isOpenEnded: controller.session?.account.isOpenEnded ?? false
                ) {
                    EmptyView()
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 1) {
                    Text(headline)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Text(Format.clock(displaySeconds))
                        .font(.system(size: 27, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText(countsDown: true))
                    Text(controller.isPaused ? "Paused" : "Remaining")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(theme.textTertiary)
                    if let session = controller.session, session.hourlyRate > 0 {
                        Text(
                            Format.money(
                                controller.elapsed / 3600 * session.hourlyRate,
                                currencyCode: session.currencyCode
                            )
                        )
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.positive)
                    }
                }
                Spacer(minLength: 0)
            }

            Button {
                controller.beginManualCapture()
            } label: {
                Label("Lock a distraction", systemImage: "lock.fill")
            }
            .buttonStyle(PrimaryButtonStyle())

            HStack(spacing: Space.xs) {
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
            }

            if controller.isPaused, let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(theme.negative)
                    .accessibilityIdentifier("anchor.focus.resume-error")
            }

            if !controller.parked.isEmpty {
                Text("\(controller.parked.count) parked this session")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private var headline: String {
        let session = controller.session
        if let intent = session?.intent, !intent.isEmpty { return intent }
        return session?.goal?.title ?? "Focusing"
    }

    private var displaySeconds: Double {
        controller.session?.account.isOpenEnded == true ? controller.elapsed : controller.remaining
    }

    // MARK: Idle

    private var idle: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let scheduledBlock, !showsAdHocComposer {
                scheduledIdle(scheduledBlock)
            } else {
                adHocComposer
            }

            if let startError {
                Label(startError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var adHocComposer: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Set your anchor")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)

            TextField("What are you working on?", text: $intent)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
                .padding(Space.xs)
                .background(theme.surfaceRaised, in: .rect(cornerRadius: Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(theme.hairline, lineWidth: 1)
                )
                .focused($intentFocused)
                .onSubmit(start)

            HStack(spacing: Space.xxs) {
                ForEach(Self.presets, id: \.self) { preset in
                    Button {
                        minutes = preset
                    } label: {
                        Text("\(preset)m")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
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

            Button(action: start) {
                Label("Start focusing", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if scheduledBlock != nil {
                Button("Use the scheduled block") {
                    showsAdHocComposer = false
                    startError = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func scheduledIdle(_ block: PlanBlock) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(scheduleEyebrow(for: block).uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(theme.textTertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                Text("\(block.plannedStart.formatted(date: .omitted, time: .shortened)) · \(Format.duration(Double(block.plannedSeconds)))")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
            }

            Button {
                start(block)
            } label: {
                Label("Start this block", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Start something else") {
                showsAdHocComposer = true
                startError = nil
                Task { @MainActor in intentFocused = true }
            }
            .buttonStyle(QuietButtonStyle())
        }
    }

    private var scheduledBlock: PlanBlock? {
        guard let record = ScheduledFocusResolver().nextBlock(
            from: blocks.map { $0.snapshot() },
            now: now
        ) else { return nil }
        return blocks.first { $0.id == record.id }
    }

    private func scheduleEyebrow(for block: PlanBlock) -> String {
        if block.plannedStart <= now, now < block.plannedEnd { return "Now" }
        if block.plannedStart > now { return "Up next" }
        return "Still open"
    }

    private func start() {
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let scheduledBlock {
            do {
                try PlanBlockFocusStarter.start(
                    scheduledBlock,
                    intent: trimmed,
                    minutes: minutes,
                    controller: controller,
                    context: context
                )
                intent = ""
                showsAdHocComposer = false
                startError = nil
            } catch {
                startError = "Focus started, but the schedule change could not be saved."
            }
            return
        }
        // Reuse a goal with the same name rather than growing a duplicate every
        // time the menu bar is used for the same work.
        let existing = goals.first { !$0.isArchived && $0.title == trimmed }
        controller.start(goal: existing, intent: trimmed, minutes: minutes)
        intent = ""
        showsAdHocComposer = false
        startError = nil
    }

    private func start(_ block: PlanBlock) {
        do {
            try PlanBlockFocusStarter.start(
                block,
                controller: controller,
                context: context
            )
            startError = nil
        } catch {
            startError = "Focus started, but the schedule link could not be saved."
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Open Anchor", action: onOpenWindow)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            if let onQuit {
                Button("Quit", action: onQuit)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}

/// The capture step, inline in the panel. A sheet cannot be presented from a
/// menu-bar window, and bouncing the user to the main window to answer "what
/// pulled you away?" would defeat the point.
struct CompactCapture: View {
    @Environment(\.anchorTheme) private var theme
    let controller: FocusController

    @State private var note = ""
    @FocusState private var focused: Bool

    private var isReturningFromPause: Bool {
        if case .returnedFromPause = controller.captureReason { return true }
        return false
    }

    private var awaySeconds: Double? {
        if case .returnedFromPause(let seconds) = controller.captureReason { return seconds }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.xxs) {
                Image(systemName: isReturningFromPause ? "arrow.uturn.left.circle" : "lock.open.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.accent)
                Text(isReturningFromPause ? "What pulled you away?" : "What's pulling at you?")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
            }

            if let awaySeconds, awaySeconds >= 5 {
                Text("You were away \(Format.duration(awaySeconds)).")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
            }

            TextField("Name it in a few words", text: $note)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
                .padding(Space.xs)
                .background(theme.surfaceRaised, in: .rect(cornerRadius: Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(theme.hairline, lineWidth: 1)
                )
                .focused($focused)
                .onSubmit(save)

            Button(action: save) {
                Label(isReturningFromPause ? "Log it" : "Park it", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !isReturningFromPause {
                Button("Pause — come back later", systemImage: "pause.fill") {
                    if controller.pauseFromCapture(note: note) { note = "" }
                }
                .buttonStyle(QuietButtonStyle())
            }

            if let error = controller.lastError { Text(error).font(.caption) }
            Button(isReturningFromPause ? "Nothing — just a break" : "Cancel") {
                controller.dismissCapture()
            }
            .buttonStyle(QuietButtonStyle(expands: false))
            .keyboardShortcut(.cancelAction)
        }
        .onAppear { focused = true }
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard controller.park(note: trimmed) != nil else { return }
        note = ""
        controller.dismissCapture()
    }
}
#endif
