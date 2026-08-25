import AnchorCore
import SwiftUI

/// The centre of the app.
///
/// Built in layers, back to front: a halo that breathes only while you are
/// actually running, a hairline track, minute ticks that fade as they are
/// consumed, the progress arc, and a head that carries the light. The clock sits
/// inside using monospaced digits so the numerals don't jitter as they change.
public struct FocusRing<Center: View>: View {
    private let fraction: Double
    private let isRunning: Bool
    private let isOpenEnded: Bool
    private let center: Center

    @Environment(\.anchorTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false
    @State private var arrivalProgress: CGFloat = 0
    @State private var arrivalOpacity: Double = 1

    public init(
        fraction: Double,
        isRunning: Bool,
        isOpenEnded: Bool = false,
        @ViewBuilder center: () -> Center
    ) {
        self.fraction = fraction
        self.isRunning = isRunning
        self.isOpenEnded = isOpenEnded
        self.center = center()
    }

    private var clamped: Double { min(1, max(0, fraction)) }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(10, side * 0.055)

            ZStack {
                halo(side: side)
                track(lineWidth: lineWidth)
                arrival(lineWidth: lineWidth)
                ticks(side: side, lineWidth: lineWidth)
                progress(lineWidth: lineWidth)
                head(side: side, lineWidth: lineWidth)
                center
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            // Only animate while running, and never when the user has asked the
            // system to reduce motion.
            guard isRunning, !reduceMotion else { return }
            withAnimation(Motion.breathe) { isBreathing = true }
        }
        .onChange(of: isRunning) { _, running in
            guard !reduceMotion else { return }
            if running {
                withAnimation(Motion.breathe) { isBreathing = true }
            } else {
                withAnimation(Motion.gentle) { isBreathing = false }
            }
        }
        .task { await revealArrival() }
        .accessibilityElement(children: .combine)
    }

    // MARK: Layers

    private func halo(side: CGFloat) -> some View {
        Circle()
            .fill(theme.haloGradient)
            .scaleEffect(isBreathing ? 1.06 : 0.96)
            .opacity(isRunning ? 1 : 0.35)
            .blur(radius: side * 0.03)
    }

    private func track(lineWidth: CGFloat) -> some View {
        Circle()
            .stroke(theme.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.06), lineWidth: lineWidth)
    }

    /// Starting Focus draws one complete line around the intention before it
    /// settles into the ordinary progress track. It explains the transition
    /// without delaying the timer or adding celebration to routine controls.
    private func arrival(lineWidth: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: arrivalProgress)
            .stroke(
                theme.accentSoft,
                style: StrokeStyle(lineWidth: max(2, lineWidth * 0.16), lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .opacity(arrivalOpacity)
    }

    @MainActor
    private func revealArrival() async {
        if reduceMotion {
            arrivalProgress = 1
            arrivalOpacity = 0
            return
        }
        withAnimation(.easeOut(duration: 0.62)) { arrivalProgress = 1 }
        try? await Task.sleep(for: .milliseconds(520))
        withAnimation(.easeOut(duration: 0.28)) { arrivalOpacity = 0 }
    }

    /// Sixty ticks, one per minute of a clock face. Consumed ticks dim, so the
    /// ring still reads as "how far through" even at a glance with no numbers.
    private func ticks(side: CGFloat, lineWidth: CGFloat) -> some View {
        let radius = side / 2 - lineWidth / 2
        return ZStack {
            ForEach(0..<60, id: \.self) { index in
                let isMajor = index % 5 == 0
                let passed = Double(index) / 60 <= clamped
                Capsule()
                    .fill(theme.textTertiary)
                    .frame(width: isMajor ? 1.6 : 1, height: isMajor ? side * 0.022 : side * 0.012)
                    .offset(y: -(radius - lineWidth * 0.9))
                    .rotationEffect(.degrees(Double(index) / 60 * 360))
                    .opacity(isOpenEnded ? 0.18 : (passed ? 0.08 : 0.3))
            }
        }
        .animation(Motion.gentle, value: clamped)
    }

    private func progress(lineWidth: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: isOpenEnded ? 1 : clamped)
            .stroke(
                theme.focusGradient,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            // `trim` starts at 3 o'clock; rotate so the ring fills from the top.
            .rotationEffect(.degrees(-90))
            .opacity(isOpenEnded ? 0.28 : 1)
            .shadow(color: theme.accent.opacity(isRunning ? 0.45 : 0.15), radius: lineWidth * 0.7)
            .animation(Motion.gentle, value: clamped)
    }

    /// The bright point at the leading edge. Sells the ring as something moving
    /// rather than a static gauge.
    @ViewBuilder
    private func head(side: CGFloat, lineWidth: CGFloat) -> some View {
        if !isOpenEnded, clamped > 0.001 {
            let radius = side / 2 - lineWidth / 2
            Circle()
                .fill(theme.accentSoft)
                .frame(width: lineWidth * 0.52, height: lineWidth * 0.52)
                .shadow(color: theme.accentSoft.opacity(0.9), radius: lineWidth * 0.6)
                .offset(y: -radius)
                .rotationEffect(.degrees(clamped * 360))
                .opacity(isRunning ? 1 : 0.5)
                .animation(Motion.gentle, value: clamped)
        }
    }
}

/// The clock that sits inside the ring.
public struct FocusClock: View {
    private let seconds: Double
    private let caption: String
    private let subcaption: String?

    @Environment(\.anchorTheme) private var theme

    public init(seconds: Double, caption: String, subcaption: String? = nil) {
        self.seconds = seconds
        self.caption = caption
        self.subcaption = subcaption
    }

    public var body: some View {
        VStack(spacing: Space.xs) {
            Text(caption.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(theme.textTertiary)

            Text(Format.clock(seconds))
                .font(.system(size: 64, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)
                // Digits roll rather than pop.
                .contentTransition(.numericText(countsDown: true))
                .animation(Motion.snappy, value: Int(seconds))
                .minimumScaleFactor(0.4)
                .lineLimit(1)

            if let subcaption {
                Text(subcaption)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, Space.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption). \(Format.duration(seconds)) \(subcaption ?? "")")
    }
}
