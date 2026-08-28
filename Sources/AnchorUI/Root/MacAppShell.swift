#if os(macOS)
import AnchorCore
import SwiftUI

/// Pure window metrics keep the Mac shell driven by available space instead of
/// device guesses. The breakpoints preserve at least 640 points for operating
/// content at every supported window width.
struct MacShellMetrics: Equatable, Sendable {
    enum RailPresentation: Equatable, Sendable {
        case icons
        case labeled
        case expanded
    }

    let presentation: RailPresentation
    let railWidth: CGFloat
    let railInset: CGFloat
    let navigationSpacing: CGFloat
    let compactHeight: Bool

    init(width: CGFloat, height: CGFloat) {
        compactHeight = height < 640
        navigationSpacing = compactHeight ? Space.xxs : Space.xs

        if width < 840 {
            presentation = .icons
            railWidth = 76
            railInset = Space.sm
        } else if width < 1_200 {
            presentation = .labeled
            railWidth = 184
            railInset = Space.md
        } else {
            presentation = .expanded
            railWidth = 216
            railInset = Space.md
        }
    }

    var showsLabels: Bool { presentation != .icons }
    var showsBrandPromise: Bool { presentation == .expanded && !compactHeight }
    var showsSessionClock: Bool { presentation != .icons }
    var workspaceMaxWidth: CGFloat {
        switch presentation {
        case .icons: 680
        case .labeled: 720
        case .expanded: 960
        }
    }
}

struct MacAppShell<Detail: View>: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding private var selection: AnchorTab
    private let controller: FocusController
    private let isSettingsSelected: Bool
    private let onSettings: () -> Void
    private let detail: Detail

    init(
        selection: Binding<AnchorTab>,
        controller: FocusController,
        isSettingsSelected: Bool,
        onSettings: @escaping () -> Void,
        @ViewBuilder detail: () -> Detail
    ) {
        _selection = selection
        self.controller = controller
        self.isSettingsSelected = isSettingsSelected
        self.onSettings = onSettings
        self.detail = detail()
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = MacShellMetrics(width: proxy.size.width, height: proxy.size.height)

            HStack(spacing: 0) {
                AnchorNavigationRail(
                    selection: $selection,
                    controller: controller,
                    metrics: metrics,
                    isSettingsSelected: isSettingsSelected,
                    onSettings: onSettings
                )
                .frame(width: metrics.railWidth)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.canvas)
                    .clipped()
                    .id(isSettingsSelected ? "settings" : selection.rawValue)
                    .transition(.opacity)
                    .environment(\.anchorWorkspaceMaxWidth, metrics.workspaceMaxWidth)
            }
            .background(theme.canvas.ignoresSafeArea())
            .animation(reduceMotion ? nil : Motion.snappy, value: metrics.presentation)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selection)
        }
    }
}

private struct AnchorNavigationRail: View {
    @Environment(\.anchorTheme) private var theme
    @Binding var selection: AnchorTab
    let controller: FocusController
    let metrics: MacShellMetrics
    let isSettingsSelected: Bool
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.bottom, metrics.compactHeight ? Space.md : Space.xl)

            VStack(spacing: metrics.navigationSpacing) {
                ForEach(Array(AnchorTab.allCases.enumerated()), id: \.element.id) { index, item in
                    MacRailDestination(
                        item: item,
                        presentation: metrics.presentation,
                        isSelected: !isSettingsSelected && selection == item,
                        carriesLiveSession: item == .focus && controller.hasSession
                    ) {
                        selection = item
                    }
                    .keyboardShortcut(
                        KeyEquivalent(Character(String(index + 1))),
                        modifiers: .command
                    )
                }
            }

            Spacer(minLength: Space.md)

            if controller.hasSession {
                sessionStatus
                    .padding(.bottom, Space.xs)
            }

            MacRailAction(
                label: "Settings",
                symbol: "gearshape",
                presentation: metrics.presentation,
                isSelected: isSettingsSelected,
                action: onSettings
            )
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, metrics.railInset)
        .padding(.top, metrics.compactHeight ? Space.sm : Space.lg)
        .padding(.bottom, Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.surface.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.hairline)
                .frame(width: 1)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var brand: some View {
        if metrics.showsLabels {
            HStack(spacing: Space.sm) {
                AnchorFaceMark(size: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Anchor")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    if metrics.showsBrandPromise {
                        Text("Draw the day")
                            .font(.caption)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        } else {
            AnchorFaceMark(size: 42)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Anchor")
        }
    }

    private var sessionStatus: some View {
        Button { selection = .focus } label: {
            if metrics.showsSessionClock {
                HStack(spacing: Space.xs) {
                    Circle()
                        .fill(controller.isRunning ? theme.accent : theme.textTertiary)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(controller.isRunning ? "In focus" : "Paused")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.textSecondary)
                        Text(sessionClock)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs)
            } else {
                ZStack {
                    Circle().fill(theme.accent.opacity(0.12))
                    Image(systemName: controller.isRunning ? "scope" : "pause.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(controller.isRunning ? theme.accent : theme.textSecondary)
                }
                .frame(width: 44, height: 44)
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(MacRailSurfaceButtonStyle())
        .help("\(controller.isRunning ? "In focus" : "Paused") · \(sessionClock)")
        .accessibilityLabel("\(controller.isRunning ? "In focus" : "Paused"), \(sessionClock)")
    }

    private var sessionClock: String {
        Format.clock(
            controller.session?.account.isOpenEnded == true
                ? controller.elapsed
                : controller.remaining
        )
    }
}

private struct MacRailDestination: View {
    @Environment(\.anchorTheme) private var theme
    let item: AnchorTab
    let presentation: MacShellMetrics.RailPresentation
    let isSelected: Bool
    let carriesLiveSession: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 17, weight: .semibold))
                        .symbolVariant(isSelected ? .fill : .none)
                        .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                        .frame(width: 36, height: 36)
                    if carriesLiveSession {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(theme.surface, lineWidth: 2))
                    }
                }

                if presentation != .icons {
                    Text(item.label)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, presentation == .icons ? 0 : Space.xs)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(backgroundColor)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.label)
        .accessibilityIdentifier("anchor.mac.nav.\(item.rawValue)")
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private var backgroundColor: Color {
        if isSelected { return theme.accent.opacity(theme.isDark ? 0.15 : 0.1) }
        if isHovering { return theme.surfaceRaised.opacity(0.86) }
        return .clear
    }
}

private struct MacRailAction: View {
    @Environment(\.anchorTheme) private var theme
    let label: String
    let symbol: String
    let presentation: MacShellMetrics.RailPresentation
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                    .frame(width: 36, height: 36)
                if presentation != .icons {
                    Text(label)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, presentation == .icons ? 0 : Space.xs)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(
                        isSelected
                            ? theme.accent.opacity(theme.isDark ? 0.15 : 0.1)
                            : (isHovering ? theme.surfaceRaised.opacity(0.86) : .clear)
                    )
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MacRailSurfaceButtonStyle: ButtonStyle {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .background(theme.surfaceRaised.opacity(configuration.isPressed ? 0.7 : 0.46), in: .rect(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1)
            )
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .animation(reduceMotion ? nil : Motion.snappy, value: configuration.isPressed)
    }
}

private struct AnchorFaceMark: View {
    @Environment(\.anchorTheme) private var theme
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.accent.opacity(theme.isDark ? 0.16 : 0.1))
            Circle()
                .strokeBorder(theme.accent.opacity(0.24), lineWidth: 1)
            Ellipse()
                .fill(Color.black)
                .frame(width: size * 0.48, height: size * 0.42)
                .rotationEffect(.degrees(-6))
            HStack(spacing: size * 0.08) {
                Circle().fill(Color.white).frame(width: size * 0.07, height: size * 0.07)
                Circle().fill(Color.white).frame(width: size * 0.07, height: size * 0.07)
            }
            .offset(y: -size * 0.02)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
#endif
