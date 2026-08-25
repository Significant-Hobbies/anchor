#if os(macOS)
import Testing
@testable import AnchorUI

@Suite("Mac shell metrics")
struct MacShellMetricsTests {
    @Test("The minimum window uses an icon rail and preserves operating width")
    func compactWindow() {
        let metrics = MacShellMetrics(width: 720, height: 560)

        #expect(metrics.presentation == .icons)
        #expect(metrics.railWidth == 76)
        #expect(metrics.workspaceMaxWidth == 680)
        #expect(720 - metrics.railWidth >= 640)
        #expect(metrics.compactHeight)
    }

    @Test("The standard window uses labeled navigation")
    func standardWindow() {
        let metrics = MacShellMetrics(width: 1_000, height: 720)

        #expect(metrics.presentation == .labeled)
        #expect(metrics.railWidth == 184)
        #expect(metrics.workspaceMaxWidth == 720)
        #expect(1_000 - metrics.railWidth >= 640)
        #expect(!metrics.compactHeight)
    }

    @Test("A wide window earns the full brand promise")
    func wideWindow() {
        let metrics = MacShellMetrics(width: 1_440, height: 900)

        #expect(metrics.presentation == .expanded)
        #expect(metrics.railWidth == 216)
        #expect(metrics.workspaceMaxWidth == 960)
        #expect(metrics.showsBrandPromise)
    }

    @Test("A common 1264-point Mac window receives the composed wide layout")
    func commonDesktopWindow() {
        let metrics = MacShellMetrics(width: 1_264, height: 800)

        #expect(metrics.presentation == .expanded)
        #expect(metrics.railWidth == 216)
        #expect(metrics.workspaceMaxWidth == 960)
        #expect(metrics.showsBrandPromise)
    }

    @Test("Tall narrow windows keep labels without stretching the rail")
    func tallWindow() {
        let metrics = MacShellMetrics(width: 900, height: 1_100)

        #expect(metrics.presentation == .labeled)
        #expect(metrics.railWidth == 184)
        #expect(900 - metrics.railWidth >= 640)
        #expect(!metrics.compactHeight)
    }
}
#endif
