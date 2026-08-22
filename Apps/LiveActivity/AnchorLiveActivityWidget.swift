import ActivityKit
import AnchorCore
import AnchorUI
import SwiftUI
import WidgetKit

/// The iPhone Live Activity for an active Anchor focus session.
///
/// Renders from wall-clock dates in `LiveActivitySnapshot` — never from a tick
/// counter — so the countdown stays correct across sleep, relaunch, and a
/// session picked up from another device. No mutation controls: the Live
/// Activity is a glanceable mirror, not a remote control.
@main
struct AnchorLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenView(state: context.state.snapshot)
                .activityBackgroundTint(Color(hex: 0x0A0C10))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "anchor:"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DynamicIslandLeading(state: context.state.snapshot)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DynamicIslandTrailing(state: context.state.snapshot)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DynamicIslandBottom(state: context.state.snapshot)
                }
            } compactLeading: {
                Image(systemName: "scope")
                    .foregroundStyle(.white)
            } compactTrailing: {
                CompactTrailing(state: context.state.snapshot)
            } minimal: {
                Image(systemName: stateIcon(context.state.snapshot.state))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Time rendering

/// Renders the live time text from wall-clock dates. Planned sessions count
/// down to `plannedCompletionDate`; open-ended sessions count up from the run
/// start; paused sessions freeze at the same value shown inside Anchor.
@ViewBuilder
private func liveTimeText(for state: LiveActivitySnapshot) -> some View {
    if state.isOpenEnded, let start = state.elapsedReferenceDate {
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
            .monospacedDigit()
    } else if let completion = state.plannedCompletionDate {
        Text(timerInterval: Date()...completion, countsDown: true)
            .monospacedDigit()
    } else {
        Text(Format.clock(state.frozenDisplaySeconds))
            .monospacedDigit()
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let state: LiveActivitySnapshot

    var body: some View {
        HStack(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(state.intent.isEmpty ? "Focus" : state.intent)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: Space.xxs) {
                    Image(systemName: stateIcon(state.state))
                        .font(.system(size: 11))
                    Text(stateLabel)
                        .font(.system(size: 12))
                }
                .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Space.xxs) {
                liveTimeText(for: state)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                if state.interruptionCount > 0 {
                    Label("\(state.interruptionCount)", systemImage: "tray.full")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
    }

    private var stateLabel: String {
        switch state.state {
        case .running: state.isOpenEnded ? "Focusing" : "Remaining"
        case .paused: "Paused"
        case .finished: "Done"
        }
    }
}

// MARK: - Dynamic Island

private struct DynamicIslandLeading: View {
    let state: LiveActivitySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: stateIcon(state.state))
                .font(.system(size: 14))
                .foregroundStyle(.white)
            Text(state.intent.isEmpty ? "Focus" : state.intent)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}

private struct DynamicIslandTrailing: View {
    let state: LiveActivitySnapshot

    var body: some View {
        liveTimeText(for: state)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
    }
}

private struct DynamicIslandBottom: View {
    let state: LiveActivitySnapshot

    var body: some View {
        HStack {
            if state.interruptionCount > 0 {
                Label("\(state.interruptionCount) parked", systemImage: "tray.full")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Link(destination: URL(string: "anchor:")!) {
                Text("Open Anchor")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x3B82F6))
            }
        }
    }
}

private struct CompactTrailing: View {
    let state: LiveActivitySnapshot

    var body: some View {
        liveTimeText(for: state)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
    }
}

// MARK: - Helpers

private func stateIcon(_ state: SessionState) -> String {
    switch state {
    case .running: "scope"
    case .paused: "pause.circle"
    case .finished: "checkmark.circle"
    }
}
