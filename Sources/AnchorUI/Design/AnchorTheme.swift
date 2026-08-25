import AnchorCore
import SwiftData
import SwiftUI

/// Anchor's visual language.
///
/// The app has one job at its centre — hold your attention on a single number —
/// so the design is built around subtraction. One accent colour, one bright
/// surface, everything else recedes. The interface itself is ink and paper;
/// colour belongs to authored doodles and meaningful state.
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
    public var onAccent: Color

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
    /// The night palette is charcoal rather than blue-black. Primary controls
    /// reverse to warm paper; small illustration and state colours carry the
    /// personality without tinting the whole application.
    public static let dark = AnchorTheme(
        canvas: Color(hex: 0x0B0B0C),
        surface: Color(hex: 0x151515),
        surfaceRaised: Color(hex: 0x202020),
        hairline: Color.white.opacity(0.09),
        textPrimary: Color(hex: 0xF2F0EA),
        textSecondary: Color(hex: 0xAAA8A2),
        textTertiary: Color(hex: 0x89867F),
        accent: Color(hex: 0xF2F0EA),
        accentSoft: Color(hex: 0xC7C4BD),
        accentDeep: Color(hex: 0x85817A),
        onAccent: Color(hex: 0x111111),
        positive: Color(hex: 0x72A982),
        caution: Color(hex: 0xE1AD4A),
        negative: Color(hex: 0xE66A5C),
        isDark: true
    )

    public static let light = AnchorTheme(
        canvas: Color(hex: 0xF3F1EC),
        surface: Color(hex: 0xFBFAF7),
        surfaceRaised: Color(hex: 0xE9E6DF),
        hairline: Color.black.opacity(0.10),
        textPrimary: Color(hex: 0x171717),
        textSecondary: Color(hex: 0x5E5B56),
        textTertiary: Color(hex: 0x6B6761),
        accent: Color(hex: 0x191919),
        accentSoft: Color(hex: 0x5B5852),
        accentDeep: Color(hex: 0x000000),
        onAccent: Color(hex: 0xF8F7F3),
        positive: Color(hex: 0x4F7D61),
        caution: Color(hex: 0x8A5B12),
        negative: Color(hex: 0xB94F43),
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

    /// Goal colour is deliberately quieter than illustration colour.
    public static let goalTints: [Color] = [
        Color(hex: 0x4F4D49), Color(hex: 0x77736C), Color(hex: 0x6D655D),
        Color(hex: 0x8A7350), Color(hex: 0x7C5F5B), Color(hex: 0x5E6B68),
        Color(hex: 0x6F6877), Color(hex: 0x64705B),
    ]

    public static func tint(_ index: Int) -> Color {
        goalTints[abs(index) % goalTints.count]
    }

    /// Distraction colours encode *origin*, not category, so the chart reads at a
    /// glance. Deliberately kept clear of the neutral focus accent: nothing that
    /// interrupts you should resemble a primary focus action.
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

private struct AnchorWorkspaceMaxWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 720
}

public extension EnvironmentValues {
    var anchorTheme: AnchorTheme {
        get { self[AnchorThemeKey.self] }
        set { self[AnchorThemeKey.self] = newValue }
    }


    /// Planning and evidence surfaces may earn more room on a genuinely wide
    /// Mac window. Focus remains intentionally narrow and does not consume it.
    var anchorWorkspaceMaxWidth: CGFloat {
        get { self[AnchorWorkspaceMaxWidthKey.self] }
        set { self[AnchorWorkspaceMaxWidthKey.self] = newValue }
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

/// Resolves one CloudKit-backed appearance choice for every Anchor scene. The
/// absence of a record uses Anchor's dark product default, so first launch is
/// consistent across devices without having to write a preference.
public struct AnchorAppearanceProvider: ViewModifier {
    @Environment(\.colorScheme) private var systemScheme
    @Query(sort: \AnchorPreferences.updatedAt, order: .reverse)
    private var preferences: [AnchorPreferences]

    private var appearance: AnchorAppearance {
        AnchorPreferencesPolicy.appearance(in: preferences)
    }

    private var resolvedScheme: ColorScheme {
        switch appearance {
        case .system: systemScheme
        case .light: .light
        case .dark: .dark
        }
    }

    public func body(content: Content) -> some View {
        content
            .environment(\.anchorTheme, .resolve(resolvedScheme))
            .preferredColorScheme(appearance.preferredColorScheme)
    }
}

private extension AnchorAppearance {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

public extension View {
    func anchorTheme() -> some View {
        modifier(AnchorThemeProvider())
    }

    /// Use at scene roots. Settings, screens, and components then inherit the
    /// same appearance instead of each platform resolving it independently.
    func anchorAppearance() -> some View {
        modifier(AnchorAppearanceProvider())
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
