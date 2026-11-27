#if !os(watchOS)
import SwiftUI

struct CalendarDrag {
    enum Source { case plan, actual }
    let id: UUID
    let source: Source
    var resizing = false
}

@MainActor
final class CalendarEntryInteraction {
    private var lastDrag: ContinuousClock.Instant?
    func noteDrag() { lastDrag = .now }
    var acceptsTap: Bool { lastDrag.map { $0.duration(to: .now) > .milliseconds(180) } ?? true }
}

struct CalendarEntryGesture: ViewModifier {
    let interaction: CalendarEntryInteraction
    let commit: (CGPoint, Bool) -> Void
    @GestureState private var drag: DragGesture.Value?

    @State private var frame = CGRect.zero

    private func resizes(_ value: DragGesture.Value) -> Bool {
        value.startLocation.x >= frame.maxX - 17 && value.startLocation.y >= frame.maxY - min(14, frame.height)
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
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("anchor.day.grid")) } action: { frame = $0 }
            .simultaneousGesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("anchor.day.grid"))
                .updating($drag) { value, state, _ in state = value }
                .onChanged { _ in interaction.noteDrag() }
                .onEnded { interaction.noteDrag(); commit($0.location, resizes($0)) })
            .zIndex(drag == nil ? 0 : 1)
    }
}
#endif
