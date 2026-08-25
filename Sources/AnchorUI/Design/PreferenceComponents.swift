import SwiftUI

/// State-free settings primitives. They intentionally know nothing about
/// AnchorCore, persistence, accounts, or navigation, so the mechanics can move
/// into a Significant Hobbies design package without dragging product behavior
/// with them. Product screens supply all copy, actions, and trailing controls.
public struct PreferenceGroup<Content: View>: View {
    @Environment(\.anchorTheme) private var theme
    private let title: String
    private let subtitle: String?
    private let content: Content

    public init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Space.xxs)

            VStack(spacing: 0) { content }
                .background(theme.surface, in: .rect(cornerRadius: Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(theme.hairline, lineWidth: 1)
                )
                .shadow(
                    color: .black.opacity(theme.isDark ? 0.20 : 0.045),
                    radius: 16,
                    y: 6
                )
        }
    }
}

public struct PreferenceActionRow: View {
    @Environment(\.anchorTheme) private var theme
    private let systemImage: String
    private let title: String
    private let detail: String
    private let tint: Color?
    private let action: () -> Void

    public init(
        systemImage: String,
        title: String,
        detail: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            PreferenceRowContent(
                systemImage: systemImage,
                title: title,
                detail: detail,
                tint: tint,
                trailing: Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textTertiary)
            )
        }
        .buttonStyle(.plain)
    }
}

public struct PreferenceInfoRow<Trailing: View>: View {
    private let systemImage: String
    private let title: String
    private let detail: String
    private let tint: Color?
    private let trailing: Trailing

    public init(
        systemImage: String,
        title: String,
        detail: String,
        tint: Color? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.tint = tint
        self.trailing = trailing()
    }

    public var body: some View {
        PreferenceRowContent(
            systemImage: systemImage,
            title: title,
            detail: detail,
            tint: tint,
            trailing: trailing
        )
    }
}

public extension PreferenceInfoRow where Trailing == EmptyView {
    init(
        systemImage: String,
        title: String,
        detail: String,
        tint: Color? = nil
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            detail: detail,
            tint: tint
        ) { EmptyView() }
    }
}

public struct PreferenceDivider: View {
    @Environment(\.anchorTheme) private var theme

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(theme.hairline)
            .frame(height: 1)
            .padding(.leading, 60)
            .accessibilityHidden(true)
    }
}

private struct PreferenceRowContent<Trailing: View>: View {
    @Environment(\.anchorTheme) private var theme
    let systemImage: String
    let title: String
    let detail: String
    let tint: Color?
    let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Space.sm) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(tint ?? theme.textSecondary)
                .frame(width: 36, height: 36)
                .background((tint ?? theme.textSecondary).opacity(0.10), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.sm)
            trailing
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(.rect)
    }
}
