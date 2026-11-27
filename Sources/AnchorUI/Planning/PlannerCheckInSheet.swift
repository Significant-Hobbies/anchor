#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

#if DEBUG
// Manual demo sessions get disposable sidecars alongside their in-memory models.
private let demoPlannerURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("anchor-demo-" + UUID().uuidString)
#endif

extension ModelContext {
    var plannerSidecarURL: URL? {
        guard let config = container.configurations.first else { return nil }
        if !config.isStoredInMemoryOnly { return config.url }
        #if DEBUG
        if DemoData.isRequested { return demoPlannerURL }
        #endif
        return nil
    }

    var plannerCheckInStore: PlannerCheckInStore? {
        plannerSidecarURL.map { PlannerCheckInStore(storeURL: $0) }
    }

    func savePlannerCheckIn(_ record: PlannerCheckIn) throws {
        guard let store = plannerCheckInStore else { throw CocoaError(.fileWriteUnknown) }
        try store.save(record)
        NotificationCenter.default.post(name: .plannerCheckInsChanged, object: nil)
    }
}

extension Notification.Name {
    static let plannerCheckInsChanged = Notification.Name("anchor.planner.check-ins.changed")
}

extension PlannerCheckIn {
    init(block: PlanBlock) {
        self.init(id: block.id, title: block.title, plannedStart: block.plannedStart,
                  outcome: .successful, reason: "")
    }
}

struct PlannerCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.anchorTheme) private var theme
    let entry: PlannerCheckIn
    let onSave: (PlannerCheckIn) throws -> Void
    @State private var outcome: PlannerOutcome?
    @State private var reason: String
    @State private var saveError = false

    init(entry: PlannerCheckIn, previous: PlannerCheckIn?, onSave: @escaping (PlannerCheckIn) throws -> Void) {
        self.entry = entry
        self.onSave = onSave
        _outcome = State(initialValue: previous?.outcome)
        _reason = State(initialValue: previous?.reason ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text(entry.title).font(.title2.weight(.semibold))
                    ForEach(PlannerOutcome.allCases, id: \.self) { choice in
                        Button {
                            outcome = choice
                        } label: {
                            HStack {
                                Label(choice.rawValue, systemImage: choice.symbol)
                                Spacer()
                                Image(systemName: outcome == choice ? "checkmark.circle.fill" : "circle")
                            }
                            .padding(Space.md)
                            .background(theme.surface, in: .rect(cornerRadius: Radius.md))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(outcome == choice ? .isSelected : [])
                    }
                    if outcome == .blocked {
                        TextField("What blocked you?", text: $reason, axis: .vertical)
                            .lineLimit(2...5).textFieldStyle(.roundedBorder)
                    }
                    Text("Check-ins are private to this device.").font(.footnote).foregroundStyle(theme.textSecondary)
                    if saveError {
                        Text("Couldn’t save this check-in. Your draft is still here.").foregroundStyle(theme.negative)
                    }
                }
                .padding(Space.lg)
            }
            .background(theme.canvas)
            .navigationTitle("Check in")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let outcome else { return }
                        do {
                            try onSave(PlannerCheckIn(id: entry.id, title: entry.title, plannedStart: entry.plannedStart,
                                                      outcome: outcome, reason: reason))
                            dismiss()
                        } catch { saveError = true }
                    }
                    .disabled(outcome == nil || (outcome == .blocked && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 400)
        #endif
    }
}
#endif
