// Mac and iPhone screens. The watch is a genuinely different shape — no
// file exporter, no pasteboard, no keyboard shortcuts — so it gets its own
// views in Watch/ rather than a pile of size guards in these.
#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

/// The live session. The ring holds the eye; everything else is one row of
/// controls and the growing list of things you refused to do instead.
public struct RunningSessionView: View {
    @Environment(\.anchorTheme) private var theme
    @Query(sort: \SavedTag.createdAt) private var savedTags: [SavedTag]
    private let controller: FocusController

    public init(controller: FocusController) {
        self.controller = controller
    }

    private var session: FocusSession? { controller.session }

    public var body: some View {
        ScrollView {
            VStack(spacing: Space.lg) {
                title

                FocusRing(
                    fraction: controller.fraction,
                    isRunning: controller.isRunning,
                    isOpenEnded: session?.account.isOpenEnded ?? false
                ) {
                    FocusClock(
                        seconds: (session?.account.isOpenEnded ?? false) ? controller.elapsed : controller.remaining,
                        caption: clockCaption,
                        subcaption: clockSubcaption
                    )
                }
                .frame(maxWidth: 340)
                .padding(.vertical, Space.xs)

                transport

                parkedList
            }
            .padding(Space.lg)
            #if os(iOS)
            // Preserve a clear scroll landing above the floating tab bar so the
            // main distraction action never reads as tucked underneath it.
            .padding(.bottom, Space.xxl)
            #endif
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center)
        }
        .background(theme.canvas)
    }

    // MARK: Pieces

    /// Headline is the session's intent; the goal appears above it only when it
    /// says something different. Starting a session with no goal creates one from
    /// the intent, so without this check the same sentence renders twice.
    private var title: some View {
        let intent = session?.intent ?? ""
        let goal = session?.goal
        let headline = intent.isEmpty ? (goal?.title ?? "Focusing") : intent
        let showGoal = goal.map { $0.title != headline } ?? false
        let tagNames = savedTags
            .filter { session?.tagIDStrings.contains($0.storageID) == true }
            .map(\.name)

        return VStack(spacing: Space.xxs) {
            if let project = session?.project {
                HStack(spacing: Space.xxs) {
                    Image(systemName: project.symbolName)
                    Text(project.name)
                }
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(AnchorTheme.tint(project.tintIndex))
            }
            if showGoal, let goal {
                HStack(spacing: Space.xxs) {
                    Image(systemName: goal.symbolName)
                        .font(.caption2.weight(.semibold))
                    Text(goal.title)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(AnchorTheme.tint(goal.tintIndex))
            }
            Text(headline)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let notes = session?.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            if !tagNames.isEmpty {
                Text(tagNames.map { "#\($0)" }.joined(separator: "  "))
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
            if let session, session.hourlyRate > 0 {
                Text(
                    "\(Format.money(controller.elapsed / 3600 * session.hourlyRate, currencyCode: session.currencyCode)) earned"
                )
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(theme.positive)
            }
        }
        .padding(.top, Space.xs)
    }

    private var clockCaption: String {
        if controller.isPaused { return "Paused" }
        if session?.account.isOpenEnded == true { return "Elapsed" }
        return "Remaining"
    }

    private var clockSubcaption: String? {
        let count = controller.parked.count
        guard count > 0 else { return nil }
        return count == 1 ? "1 thing parked" : "\(count) things parked"
    }

    private var transport: some View {
        VStack(spacing: Space.md) {
            if controller.isPaused, let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(theme.negative)
                    .accessibilityIdentifier("anchor.focus.resume-error")
            }

            // The main event: parking a distraction is the biggest, easiest target.
            Button {
                controller.beginManualCapture()
            } label: {
                HStack(spacing: Space.xs) {
                    InterruptionKnotMark(tint: theme.onAccent)
                    Text("Lock a distraction")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut("l", modifiers: [.command, .shift])

            HStack(spacing: Space.lg) {
                Button {
                    controller.isPaused ? controller.resume() : controller.pause()
                } label: {
                    Label(controller.isPaused ? "Resume" : "Pause", systemImage: controller.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(QuietButtonStyle(expands: false))
                .help(controller.isPaused ? "Resume" : "Pause")
                .accessibilityLabel(controller.isPaused ? "Resume" : "Pause")

                Button {
                    controller.end(reason: .endedEarly)
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(CircleButtonStyle())
                .help("End session")
                .accessibilityLabel("End session")
            }
        }
    }

    @ViewBuilder
    private var parkedList: some View {
        let parked = controller.parked
        if !parked.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader(
                        "Parked",
                        subtitle: "Waiting for you. Not now."
                    )
                    ForEach(parked) { distraction in
                        HStack(spacing: Space.sm) {
                            KindGlyph(distraction.displayKind, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(distraction.privateNote.isEmpty ? "Private note unavailable on this device" : distraction.privateNote)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(theme.textPrimary)
                                    .lineLimit(2)
                                Text(distraction.displayKind.label)
                                    .font(.caption2)
                                    .foregroundStyle(theme.textTertiary)
                            }
                            Spacer(minLength: Space.xs)
                            Text(Format.duration(distraction.offsetSeconds))
                                .font(.system(.caption2, design: .rounded).weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(theme.textTertiary)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .animation(Motion.snappy, value: parked.count)
        }
    }
}
#endif
