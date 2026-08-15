import AnchorCore
import SwiftUI

/// Anchor's visual language.
///
/// The app has one job at its centre — hold your attention on a single number —
/// so the design is built around subtraction. One accent colour, one bright
/// surface, everything else recedes. Colour is spent on the ring and on the
/// distraction categories, and nowhere else.
///
/// Tokens are resolved from the colour scheme rather than pulled from an asset
/// catalogue so the package stays resource-free and the values stay greppable.
public struct AnchorTheme: Sendable, Equatable {
    // Surfaces, back to front.
    public var canvas: Color
    public var surface: Color
    public var surfaceRaised: Color
    public var hairline: Color

    // Text, in descending emphasis.
    public var textPrimary: Color
    public var textSecondary: Color
    public var textTertiary: Color

    // The one accent.
    public var accent: Color
    public var accentSoft: Color
    public var accentDeep: Color

    // Status.
    public var positive: Color
    public var caution: Color
    public var negative: Color

    public var isDark: Bool

    public static func resolve(_ scheme: ColorScheme) -> AnchorTheme {
        scheme == .dark ? .dark : .light
    }

    /// Night is the default posture: focus sessions are long, and a bright slab
    /// of white is a poor companion for an hour.
    ///
    /// The palette carries the product's central idea: **cool is focus, warm is
    /// interruption**. Progress, the ring and every primary action are cobalt;
    /// warmth is spent only on the things that break a session. A single-hue
    /// scheme made those two read as the same thing.
    public static let dark = AnchorTheme(
        canvas: Color(hex: 0x0A0C10),
        surface: Color(hex: 0x141922),
        surfaceRaised: Color(hex: 0x1D2532),
        hairline: Color.white.opacity(0.075),
        textPrimary: Color(hex: 0xEDF1F7),
        textSecondary: Color(hex: 0x94A0B3),
        textTertiary: Color(hex: 0x636F82),
        accent: Color(hex: 0x3B82F6),
        accentSoft: Color(hex: 0x7DD3FC),
        accentDeep: Color(hex: 0x1D4ED8),
        positive: Color(hex: 0x4ADE80),
        caution: Color(hex: 0xF5B849),
        negative: Color(hex: 0xFB7185),
        isDark: true
    )

    public static let light = AnchorTheme(
        canvas: Color(hex: 0xF4F6FA),
        surface: Color(hex: 0xFFFFFF),
        surfaceRaised: Color(hex: 0xF7F9FC),
        hairline: Color.black.opacity(0.07),
        textPrimary: Color(hex: 0x0F172A),
        textSecondary: Color(hex: 0x53607A),
        textTertiary: Color(hex: 0x8593AC),
        accent: Color(hex: 0x2563EB),
        accentSoft: Color(hex: 0x3B82F6),
        accentDeep: Color(hex: 0x1E40AF),
        positive: Color(hex: 0x16A34A),
        caution: Color(hex: 0xC2810C),
        negative: Color(hex: 0xE11D48),
        isDark: false
    )

    /// The ring's sweep: deep at the start, luminous at the finish. Multi-stop so
    /// the arc has somewhere to travel rather than reading as one flat colour.
    public var focusGradient: AngularGradient {
        AngularGradient(
            colors: [accentDeep, accent, accentSoft, accent, accentDeep],
            center: .center,
            angle: .degrees(-90)
        )
    }

    /// Used behind the ring so the glow reads as light rather than as a shape.
    public var haloGradient: RadialGradient {
        RadialGradient(
            colors: [accent.opacity(isDark ? 0.22 : 0.14), .clear],
            center: .center,
            startRadius: 8,
            endRadius: 220
        )
    }

    /// Eight tints for goals, evenly spaced round the wheel and matched in
    /// saturation so no single goal shouts louder than another.
    public static let goalTints: [Color] = [
        Color(hex: 0x3B82F6), Color(hex: 0x7DD3FC), Color(hex: 0xA78BFA),
        Color(hex: 0xF5B849), Color(hex: 0xFB7185), Color(hex: 0x38BDF8),
        Color(hex: 0x818CF8), Color(hex: 0x2DD4BF),
    ]

    public static func tint(_ index: Int) -> Color {
        goalTints[abs(index) % goalTints.count]
    }

    /// Distraction colours encode *origin*, not category, so the chart reads at a
    /// glance. Deliberately kept clear of the cobalt accent: nothing that
    /// interrupts you should wear the colour of focus.
    public func color(for kind: DistractionKind) -> Color {
        color(for: kind.origin)
    }

    public func color(for origin: DistractionOrigin) -> Color {
        switch origin {
        case .external: Color(hex: 0xFB7185)   // the world came to you
        case .internal: Color(hex: 0xA78BFA)   // you went to it
        case .mixed: Color(hex: 0xF5B849)
        }
    }
}

// MARK: - Environment

private struct AnchorThemeKey: EnvironmentKey {
    static let defaultValue = AnchorTheme.dark
}

public extension EnvironmentValues {
    var anchorTheme: AnchorTheme {
        get { self[AnchorThemeKey.self] }
        set { self[AnchorThemeKey.self] = newValue }
    }
}

/// Resolves the theme from the live colour scheme and injects it. Applied once
/// at the root of each app.
public struct AnchorThemeProvider: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    public func body(content: Content) -> some View {
        content.environment(\.anchorTheme, .resolve(scheme))
    }
}

public extension View {
    func anchorTheme() -> some View {
        modifier(AnchorThemeProvider())
    }
}

// MARK: - Scale

/// One spacing scale, used everywhere. Values are multiples of 4 so optical
/// alignment stays predictable across the two platforms.
public enum Space {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48
}

public enum Radius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 14
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 28
}

/// Motion is one spring, reused. Consistent physics is most of what makes an
/// interface feel like a single object rather than a pile of screens.
public enum Motion {
    public static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)
    public static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.85)
    public static let breathe = Animation.easeInOut(duration: 4).repeatForever(autoreverses: true)
}

// MARK: - Colour helper

public extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
