import AnchorCore
import SwiftUI

// MARK: - Surfaces

/// The one card in the app. Everything that needs to sit above the canvas uses it.
public struct Card<Content: View>: View {
    @Environment(\.anchorTheme) private var theme
    private let padding: CGFloat
    private let content: Content

    public init(padding: CGFloat = Space.md, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: .rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(theme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(theme.isDark ? 0.28 : 0.05), radius: 18, y: 6)
    }
}

/// Section heading with an optional trailing control.
public struct SectionHeader<Trailing: View>: View {
    @Environment(\.anchorTheme) private var theme
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            Spacer(minLength: Space.sm)
            trailing
        }
    }
}

// MARK: - Buttons

/// The single filled action on a screen. There is never more than one.
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    public var isDestructive: Bool = false

    public init(isDestructive: Bool = false) {
        self.isDestructive = isDestructive
    }

    public func makeBody(configuration: Configuration) -> some View {
        let tint = isDestructive ? theme.negative : theme.accent
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            // White throughout: the accent is dark enough in both schemes to
            // carry it, and a single on-accent colour keeps the button reading
            // the same everywhere.
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.55))
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(tint.opacity(isEnabled ? 1 : 0.3), in: .capsule)
            .shadow(color: tint.opacity(isEnabled ? 0.35 : 0), radius: 14, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// Everything that isn't the primary action.
public struct QuietButtonStyle: ButtonStyle {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    public var expands: Bool = true

    public init(expands: Bool = true) {
        self.expands = expands
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(theme.textPrimary.opacity(isEnabled ? 1 : 0.4))
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: 44)
            .background(theme.surfaceRaised, in: .capsule)
            .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// Circular control used for the transport buttons under the ring.
public struct CircleButtonStyle: ButtonStyle {
    @Environment(\.anchorTheme) private var theme
    public var diameter: CGFloat = 52
    public var isProminent: Bool = false

    public init(diameter: CGFloat = 52, isProminent: Bool = false) {
        self.diameter = diameter
        self.isProminent = isProminent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.36, weight: .semibold))
            .foregroundStyle(isProminent ? Color.white : theme.textPrimary)
            .frame(width: diameter, height: diameter)
            .background(isProminent ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.surfaceRaised), in: .circle)
            .overlay(Circle().strokeBorder(theme.hairline, lineWidth: isProminent ? 0 : 1))
            .shadow(color: isProminent ? theme.accent.opacity(0.35) : .clear, radius: 14, y: 4)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

// MARK: - Small parts

/// Label + number. The unit of the analytics screen.
public struct StatTile: View {
    @Environment(\.anchorTheme) private var theme
    private let label: String
    private let value: String
    private let detail: String?
    private let symbol: String
    private let tint: Color?

    public init(label: String, value: String, detail: String? = nil, symbol: String, tint: Color? = nil) {
        self.label = label
        self.value = value
        self.detail = detail
        self.symbol = symbol
        self.tint = tint
    }

    public var body: some View {
        Card(padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.xxs) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint ?? theme.accent)
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                Text(value)
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value). \(detail ?? "")")
    }
}

/// Small pill. Used for categories, durations and filters.
public struct Chip: View {
    @Environment(\.anchorTheme) private var theme
    private let text: String
    private let symbol: String?
    private let tint: Color?
    private let isSelected: Bool

    public init(_ text: String, symbol: String? = nil, tint: Color? = nil, isSelected: Bool = false) {
        self.text = text
        self.symbol = symbol
        self.tint = tint
        self.isSelected = isSelected
    }

    public var body: some View {
        let color = tint ?? theme.accent
        HStack(spacing: Space.xxs) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundStyle(isSelected ? color : theme.textSecondary)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 6)
        .background(
            (isSelected ? color.opacity(0.16) : theme.surfaceRaised),
            in: .capsule
        )
        .overlay(
            Capsule().strokeBorder(isSelected ? color.opacity(0.5) : theme.hairline, lineWidth: 1)
        )
    }
}

/// Horizontal proportion bar used in the distraction leaderboard.
public struct ProportionBar: View {
    @Environment(\.anchorTheme) private var theme
    private let fraction: Double
    private let tint: Color

    public init(fraction: Double, tint: Color) {
        self.fraction = fraction
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.hairline)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(3, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
        .animation(Motion.gentle, value: fraction)
    }
}

/// Shown wherever there is genuinely nothing yet. Says what to do, not "no data".
public struct EmptyStateView: View {
    @Environment(\.anchorTheme) private var theme
    private let symbol: String
    private let title: String
    private let message: String

    public init(symbol: String, title: String, message: String) {
        self.symbol = symbol
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 320)
        .padding(.vertical, Space.xl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Category glyph

/// The coloured round icon used for a distraction category, everywhere it appears.
public struct KindGlyph: View {
    @Environment(\.anchorTheme) private var theme
    private let kind: DistractionKind
    private let size: CGFloat

    public init(_ kind: DistractionKind, size: CGFloat = 30) {
        self.kind = kind
        self.size = size
    }

    public var body: some View {
        let tint = theme.color(for: kind)
        Image(systemName: kind.symbolName)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: .circle)
    }
}

/// Wrapping row of chips. `LazyVGrid` can't do variable-width items, and a
/// horizontal `ScrollView` hides options — so the chips wrap.
public struct FlowRow: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: CGFloat = 1
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var total: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + spacing + size.width > maxWidth {
                total += rowHeight + spacing
                rows += 1
                x = size.width
                rowHeight = size.height
            } else {
                x += (x > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        total += rowHeight
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: total)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
