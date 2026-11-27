#if !os(watchOS)
import AnchorCore
import SwiftUI
import UniformTypeIdentifiers

struct CalendarDrag: Codable, Transferable {
    enum Source: String, Codable { case plan, actual }
    let id: UUID
    let source: Source
    var resizing = false
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "com.significanthobbies.anchor.calendar-entry"))
            .visibility(.ownProcess)
    }
}

extension View {
    func movableEntry(_ payload: CalendarDrag, resize: Bool) -> some View {
        draggable(payload)
            .overlay(alignment: .bottomTrailing) {
                if resize {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                        .draggable(CalendarDrag(id: payload.id, source: payload.source, resizing: true))
                        .help("Drag to change the end time")
                        .accessibilityLabel("Resize entry")
                }
            }
    }
}
#endif
