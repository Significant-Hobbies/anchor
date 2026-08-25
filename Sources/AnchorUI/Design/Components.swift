import AnchorCore
import SwiftUI

// MARK: - Doodle scenes

/// A quiet editorial illustration that gives each primary surface a recognisable
/// character without turning the artwork itself into a control.
public struct DoodleScene: View {
    @Environment(\.anchorTheme) private var theme
    private let asset: String
    private let eyebrow: String?
    private let title: String
    private let message: String
    private let compact: Bool

    public init(
        _ asset: String,
        eyebrow: String? = nil,
        title: String,
        message: String,
        compact: Bool = false
    ) {
        self.asset = asset
        self.eyebrow = eyebrow
        self.title = title
        self.message = message
        self.compact = compact
    }

    public var body: some View {
        Group {
            #if os(macOS)
            // Mac content columns have plenty of width but SwiftUI can still
            // choose the stacked fallback from an image's ideal size. Keep the
            // artwork editorial and horizontal here so the actual work remains
            // above the fold.
            scene(horizontal: true)
            #else
            ViewThatFits(in: .horizontal) {
                scene(horizontal: true)
                scene(horizontal: false)
            }
            #endif
        }
        .frame(minHeight: compact ? 112 : 152)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func scene(horizontal: Bool) -> some View {
        Group {
            if horizontal {
                HStack(alignment: .center, spacing: Space.lg) {
                    copy.frame(maxWidth: .infinity, alignment: .leading)
                    artwork.frame(width: compact ? 132 : 220)
                }
            } else {
                VStack(alignment: .leading, spacing: compact ? Space.sm : Space.md) {
                    copy
                    artwork
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .tracking(1.25)
                    .foregroundStyle(theme.accent)
            }
            Text(title)
                .font(
                    .system(compact ? .title2 : .title, design: .rounded)
                        .weight(.semibold)
                )
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            DrawnUnderline(width: compact ? 48 : 64)
            .accessibilityHidden(true)
            Text(message)
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var artwork: some View {
        Image(asset)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: compact ? 104 : 152)
            .accessibilityHidden(true)
    }
}

/// A small hand-drawn stroke used as punctuation, never as an affordance. The
/// animated form is reserved for the moment Focus takes over the screen.
public struct DrawnUnderline: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: CGFloat

    private let width: CGFloat
    private let tint: Color?
    private let animated: Bool

    public init(width: CGFloat = 64, tint: Color? = nil, animated: Bool = false) {
        self.width = width
        self.tint = tint
        self.animated = animated
        _reveal = State(initialValue: animated ? 0 : 1)
    }

    public var body: some View {
        DrawnUnderlineShape()
            .trim(from: 0, to: reveal)
            .stroke(
                tint ?? theme.accent,
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
            )
            .frame(width: width, height: 8)
            .rotationEffect(.degrees(-1.2))
            .onAppear {
                guard animated, reveal < 1 else { return }
                if reduceMotion {
                    reveal = 1
                } else {
                    withAnimation(.easeOut(duration: 0.52)) { reveal = 1 }
                }
            }
    }
}

private struct DrawnUnderlineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 1, y: rect.height * 0.62))
        path.addCurve(
            to: CGPoint(x: rect.width - 5, y: rect.height * 0.42),
            control1: CGPoint(x: rect.width * 0.27, y: rect.height * 0.31),
            control2: CGPoint(x: rect.width * 0.70, y: rect.height * 0.74)
        )
        path.addEllipse(
            in: CGRect(x: rect.width - 2, y: rect.height * 0.28, width: 4, height: 4)
        )
        return path
    }
}

/// The line Anchor uses to compare the day that was drawn with the day that was
/// lived. Its slight bend keeps it authored while labels and values carry the
/// exact meaning.
public struct DrawnTrace: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: CGFloat = 0

    private let fraction: Double
    private let tint: Color

    public init(fraction: Double, tint: Color) {
        self.fraction = min(1, max(0, fraction))
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            DrawnTraceShape(fraction: 1, showsEnd: false)
                .stroke(theme.hairline, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            DrawnTraceShape(
                fraction: max(0.025, fraction) * Double(reveal),
                showsEnd: true
            )
            .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .frame(minHeight: 14)
        .onAppear {
            if reduceMotion {
                reveal = 1
            } else {
                withAnimation(.easeOut(duration: 0.68)) { reveal = 1 }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct DrawnTraceShape: Shape {
    var fraction: Double
    let showsEnd: Bool

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = CGFloat(min(1, max(0, fraction)))
        let endX = max(2, rect.width * progress)
        let start = CGPoint(x: 2, y: rect.height * 0.58)
        let end = CGPoint(x: endX, y: rect.height * 0.47)
        var path = Path()
        path.move(to: start)
        path.addCurve(
            to: end,
            control1: CGPoint(x: endX * 0.28, y: rect.height * 0.28),
            control2: CGPoint(x: endX * 0.70, y: rect.height * 0.74)
        )
        if showsEnd {
            path.addEllipse(in: CGRect(x: end.x - 2.5, y: end.y - 2.5, width: 5, height: 5))
        }
        return path
    }
}

/// A small loop in the line marks something that tried to pull the day away.
/// It is neutral at capture time; origin colour arrives only after the person or
/// on-device tagger knows what happened.
public struct InterruptionKnotMark: View {
    private let tint: Color
    private let size: CGFloat

    public init(tint: Color, size: CGFloat = 18) {
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        InterruptionKnotShape()
            .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct InterruptionKnotShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 1))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY - 1),
            control1: CGPoint(x: rect.maxX + 1, y: rect.height * 0.20),
            control2: CGPoint(x: rect.minX - 1, y: rect.height * 0.78)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + 1),
            control1: CGPoint(x: rect.maxX + 1, y: rect.height * 0.78),
            control2: CGPoint(x: rect.minX - 1, y: rect.height * 0.20)
        )
        return path
    }
}

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
    public var isDestructive: Bool = false
    public var expands: Bool = true

    public init(isDestructive: Bool = false, expands: Bool = true) {
        self.isDestructive = isDestructive
        self.expands = expands
    }

    public func makeBody(configuration: Configuration) -> some View {
        TactilePrimaryButton(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isDestructive: isDestructive,
            expands: expands
        )
    }
}

/// Everything that isn't the primary action.
public struct QuietButtonStyle: ButtonStyle {
    public var expands: Bool = true

    public init(expands: Bool = true) {
        self.expands = expands
    }

    public func makeBody(configuration: Configuration) -> some View {
        TactileQuietButton(
            label: configuration.label,
            isPressed: configuration.isPressed,
            expands: expands
        )
    }
}

/// Circular control used for the transport buttons under the ring.
public struct CircleButtonStyle: ButtonStyle {
    public var diameter: CGFloat = 52
    public var isProminent: Bool = false

    public init(diameter: CGFloat = 52, isProminent: Bool = false) {
        self.diameter = diameter
        self.isProminent = isProminent
    }

    public func makeBody(configuration: Configuration) -> some View {
        TactileCircleButton(
            label: configuration.label,
            isPressed: configuration.isPressed,
            diameter: diameter,
            isProminent: isProminent
        )
    }
}

/// The slight lower edge makes the controls feel printed and physical without
/// turning them into skeuomorphic objects. Pressing settles the face onto that
/// edge instead of simply shrinking the whole control.
private struct TactilePrimaryButton<Label: View>: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let isDestructive: Bool
    let expands: Bool

    private var tint: Color { isDestructive ? theme.negative : theme.accent }
    private var faceOffset: CGFloat { isPressed ? 2 : (isHovered && isEnabled ? -1 : 0) }

    var body: some View {
        label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(theme.onAccent.opacity(isEnabled ? 1 : 0.55))
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: 44)
            .background {
                ZStack {
                    Capsule()
                        .fill(theme.isDark ? theme.accentDeep : Color.black.opacity(0.72))
                        .offset(y: isEnabled ? 3 : 1)
                    Capsule()
                        .fill(tint.opacity(isEnabled ? 1 : 0.34))
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [theme.onAccent.opacity(0.30), theme.onAccent.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .padding(1)
                }
            }
            .contentShape(.capsule)
            .offset(y: faceOffset)
            .shadow(
                color: .black.opacity(isEnabled ? (theme.isDark ? 0.42 : 0.18) : 0),
                radius: isPressed ? 4 : 10,
                y: isPressed ? 2 : 7
            )
            .shadow(
                color: tint.opacity(isEnabled ? (isHovered ? 0.20 : 0.10) : 0),
                radius: isHovered ? 18 : 12,
                y: 2
            )
            .animation(reduceMotion ? nil : Motion.snappy, value: isPressed)
            .animation(reduceMotion ? nil : Motion.snappy, value: isHovered)
            .anchorButtonHover { isHovered = $0 }
    }
}

private struct TactileQuietButton<Label: View>: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let expands: Bool

    private var faceOffset: CGFloat { isPressed ? 1.5 : (isHovered && isEnabled ? -1 : 0) }

    var body: some View {
        label
            .font(.system(.body, design: .rounded).weight(.medium))
            .foregroundStyle(theme.textPrimary.opacity(isEnabled ? 1 : 0.4))
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: 44)
            .background {
                ZStack {
                    Capsule()
                        .fill(Color.black.opacity(theme.isDark ? 0.55 : 0.16))
                        .offset(y: isEnabled ? 2 : 1)
                    Capsule()
                        .fill(theme.surfaceRaised)
                    if isHovered && isEnabled {
                        Capsule().fill(theme.textPrimary.opacity(theme.isDark ? 0.055 : 0.035))
                    }
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: theme.isDark
                                    ? [Color.white.opacity(0.14), Color.white.opacity(0.035)]
                                    : [Color.white.opacity(0.90), Color.black.opacity(0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            }
            .contentShape(.capsule)
            .offset(y: faceOffset)
            .shadow(
                color: .black.opacity(isEnabled ? (isHovered ? 0.18 : 0.08) : 0),
                radius: isPressed ? 2 : (isHovered ? 9 : 5),
                y: isPressed ? 1 : 4
            )
            .animation(reduceMotion ? nil : Motion.snappy, value: isPressed)
            .animation(reduceMotion ? nil : Motion.snappy, value: isHovered)
            .anchorButtonHover { isHovered = $0 }
    }
}

private struct TactileCircleButton<Label: View>: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let diameter: CGFloat
    let isProminent: Bool

    private var faceOffset: CGFloat { isPressed ? 2 : (isHovered && isEnabled ? -1 : 0) }

    var body: some View {
        label
            .font(.system(size: diameter * 0.36, weight: .semibold))
            .foregroundStyle(isProminent ? theme.onAccent : theme.textPrimary)
            .frame(width: diameter, height: diameter)
            .background {
                ZStack {
                    Circle()
                        .fill(isProminent ? theme.accentDeep : Color.black.opacity(theme.isDark ? 0.55 : 0.16))
                        .offset(y: isEnabled ? 3 : 1)
                    Circle()
                        .fill(isProminent ? theme.accent : theme.surfaceRaised)
                    Circle()
                        .strokeBorder(
                            isProminent ? theme.onAccent.opacity(0.20) : theme.hairline,
                            lineWidth: 1
                        )
                        .padding(1)
                }
            }
            .contentShape(.circle)
            .offset(y: faceOffset)
            .shadow(
                color: .black.opacity(isEnabled ? (theme.isDark ? 0.40 : 0.16) : 0),
                radius: isPressed ? 3 : 9,
                y: isPressed ? 2 : 6
            )
            .animation(reduceMotion ? nil : Motion.snappy, value: isPressed)
            .animation(reduceMotion ? nil : Motion.snappy, value: isHovered)
            .anchorButtonHover { isHovered = $0 }
    }
}

private extension View {
    @ViewBuilder
    func anchorButtonHover(_ action: @escaping (Bool) -> Void) -> some View {
        #if os(macOS)
        onHover(perform: action)
        #else
        self
        #endif
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
