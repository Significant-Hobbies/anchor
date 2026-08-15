import AnchorCore
import SwiftUI

/// The live session. The ring holds the eye; everything else is one row of
/// controls and the growing list of things you refused to do instead.
public struct RunningSessionView: View {
    @Environment(\.anchorTheme) private var theme
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

                if controller.hasReachedPlan {
                    bell
                } else {
                    transport
                }

                parkedList
            }
            .padding(Space.lg)
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

        return VStack(spacing: Space.xxs) {
            if showGoal, let goal {
                HStack(spacing: Space.xxs) {
                    Image(systemName: goal.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                    Text(goal.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(AnchorTheme.tint(goal.tintIndex))
            }
            Text(headline)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
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

    /// The bell: the plan is served. Never auto-stops — deciding to continue is
    /// itself worth recording, and being yanked out of flow by a modal is worse
    /// than the timer quietly waiting.
    private var bell: some View {
        VStack(spacing: Space.sm) {
            Text("You served the full \(Format.duration(Double(session?.plannedSeconds ?? 0))).")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)

            HStack(spacing: Space.xs) {
                Button("5 more") { controller.extend(byMinutes: 5) }
                    .buttonStyle(QuietButtonStyle())
                Button("15 more") { controller.extend(byMinutes: 15) }
                    .buttonStyle(QuietButtonStyle())
            }

            Button {
                controller.end(reason: .completed)
            } label: {
                Label("Finish", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private var transport: some View {
        VStack(spacing: Space.md) {
            // The main event: parking a distraction is the biggest, easiest target.
            Button {
                controller.beginManualCapture()
            } label: {
                Label("Lock a distraction", systemImage: "lock.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut("l", modifiers: [.command, .shift])

            HStack(spacing: Space.lg) {
                Button {
                    controller.isPaused ? controller.resume() : controller.pause()
                } label: {
                    Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(CircleButtonStyle())
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
                                Text(distraction.note)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(theme.textPrimary)
                                    .lineLimit(2)
                                Text(distraction.displayKind.label)
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            Spacer(minLength: Space.xs)
                            Text(Format.duration(distraction.offsetSeconds))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
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
