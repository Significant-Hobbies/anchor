#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

/// Snapshot the occurrence before presenting a confirmation. Calendar refresh
/// can update or remove the SwiftData object while the dialog is open.
struct CalendarEventRemoval: Identifiable {
    let id: String
    let title: String

    init?(_ block: PlanBlock) {
        guard let key = block.externalEventKey else { return nil }
        id = key
        title = block.title
    }
}

struct CalendarEventRemovalDialog: ViewModifier {
    @Environment(\.modelContext) private var context
    @Binding var request: CalendarEventRemoval?
    @State private var failed = false
    let onRemove: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(item: $request) { event in
                Alert(title: Text("Remove this event from Anchor?"),
                      message: Text("“\(event.title)” will stay in Google Calendar. Future imports will skip this occurrence."),
                      primaryButton: .destructive(Text("Remove from Anchor")) {
                          do {
                              try DayPlanService(context: context).removeImportedEvent(key: event.id)
                              onRemove()
                          } catch { failed = true }
                      }, secondaryButton: .cancel())
            }
            .alert("Couldn’t remove this event", isPresented: $failed) {
                Button("OK") {}
            } message: {
                Text("Open the event and try again.")
            }
    }
}
#endif
