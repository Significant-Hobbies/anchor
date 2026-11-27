#if !os(watchOS)
import SwiftUI

struct CalendarDrag {
    enum Source { case plan, actual }
    let id: UUID
    let source: Source
    var resizing = false
    var keepsTime = false
}

@MainActor
final class CalendarEntryInteraction {
    private var lastDrag: ContinuousClock.Instant?
    func noteDrag() { lastDrag = .now }
    var acceptsTap: Bool { lastDrag.map { $0.duration(to: .now) > .milliseconds(180) } ?? true }
}

struct CalendarEntryGesture: ViewModifier {
    let interaction: CalendarEntryInteraction
    let commit: (CGPoint, Bool, Bool) -> Void
    @GestureState private var drag: DragGesture.Value?

    private struct Frames: Equatable {
        var grid = CGRect.zero
        var screen = CGRect.zero
    }
    @State private var frame = Frames()
    @State private var grabOffset: CGFloat?
    @State private var draggingEnd = false

    private func resizes(_ value: DragGesture.Value) -> Bool {
        value.startLocation.x >= frame.screen.maxX - 17 && value.startLocation.y >= frame.screen.maxY - min(14, frame.screen.height)
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.and.down")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }
            .offset(x: drag.map { resizes($0) ? 0 : $0.translation.width } ?? 0,
                    y: drag.map { resizes($0) ? 0 : $0.translation.height } ?? 0)
            .onGeometryChange(for: Frames.self) {
                Frames(grid: $0.frame(in: .named("anchor.day.grid")), screen: $0.frame(in: .global))
            } action: { frame = $0 }
            .simultaneousGesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .updating($drag) { value, state, _ in state = value }
                .onChanged { value in
                    interaction.noteDrag()
                    if grabOffset == nil {
                        draggingEnd = resizes(value)
                        grabOffset = value.startLocation.y - (draggingEnd ? frame.screen.maxY : frame.screen.minY)
                    }
                }
                .onEnded { value in
                    interaction.noteDrag()
                    let point = CGPoint(x: value.location.x - frame.screen.minX + frame.grid.minX,
                                        y: value.location.y - frame.screen.minY + frame.grid.minY - (grabOffset ?? 0))
                    commit(point, draggingEnd, abs(value.translation.height) < 3)
                    grabOffset = nil
                })
            .onChange(of: drag == nil) { _, idle in if idle { grabOffset = nil } }
            .zIndex(drag == nil ? 0 : 1)
    }
}
#endif
