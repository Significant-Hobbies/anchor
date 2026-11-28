#if !os(watchOS)
import AnchorCore
import SwiftUI

struct DailyChecklistButton: View {
    let day: Date
    let store: DailyChecklistStore
    let hitSize: CGFloat
    @State private var showingChecklist = false

    var body: some View {
        Button { showingChecklist.toggle() } label: {
            ViewThatFits(in: .horizontal) {
                Label("Checklist", systemImage: "checklist").fixedSize()
                Image(systemName: "checklist")
            }
            .font(.subheadline.weight(.medium))
            .frame(minWidth: hitSize, minHeight: hitSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Daily checklist")
        .accessibilityIdentifier("anchor.today.checklist")
        .popover(isPresented: $showingChecklist) {
            DailyChecklistView(store: store, day: day, hitSize: hitSize)
                .anchorTheme()
        }
    }
}

private struct DailyChecklistView: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    let store: DailyChecklistStore
    let day: Date
    let hitSize: CGFloat
    @State private var checklist: DailyChecklist?
    @State private var yesterday = false
    @State private var isEditing = false
    @State private var canRecover = false
    @State private var title = ""
    @State private var message: String?
    @FocusState private var enteringTitle: Bool

    var body: some View {
        TimelineView(.everyMinute) { clock in
            let dates = DailyChecklist.availableDates(at: clock.date)
            let key = yesterday ? (dates.last ?? "") : (dates.first ?? "")
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack {
                    Text("Daily checklist").font(.headline)
                    Spacer()
                    if let checklist, !checklist.items.isEmpty || isEditing {
                        Button(isEditing ? "Done" : "Edit") {
                            isEditing.toggle()
                            enteringTitle = isEditing
                        }
                    }
                    #if !os(macOS)
                    Button("Close checklist", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                    #endif
                }

                if let checklist {
                    Picker("Checklist day", selection: $yesterday) {
                        Text("Today").tag(false)
                        Text("Yesterday").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    if !checklist.items.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                ForEach(checklist.items) { item in
                                    row(item, date: key)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(maxHeight: 240)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if isEditing || checklist.items.isEmpty {
                        HStack(spacing: Space.xs) {
                            TextField("New checklist item", text: $title)
                                .textFieldStyle(.roundedBorder)
                                .focused($enteringTitle)
                                .onSubmit(add)
                            Button("Add", action: add)
                                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                if let message {
                    Text(message).font(.footnote).foregroundStyle(theme.caution)
                }
                if checklist == nil {
                    if canRecover {
                        Button("Start a new checklist") { save { try store.recover() } }
                    } else {
                        Button("Retry", action: reload)
                    }
                }
            }
            .padding(Space.md)
        }
        #if os(macOS)
        .frame(width: 318)
        #else
        .frame(width: sizeClass == .regular ? 318 : nil)
        .presentationDetents([.medium, .large])
        #endif
        .background(theme.canvas)
        .onAppear {
            yesterday = DailyChecklist.availableDates(at: Date()).last == DailyChecklist.dateKey(for: day)
            reload()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
    }

    private func row(_ item: DailyChecklist.Item, date: String) -> some View {
        let isChecked = item.isChecked(on: date)
        return HStack {
            Button {
                save { try store.setChecked(!isChecked, itemID: item.id, on: date) }
            } label: {
                HStack(spacing: Space.xs) {
                    Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isChecked ? theme.positive : theme.textSecondary)
                        .accessibilityHidden(true)
                    Text(item.title)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: max(30, hitSize), alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isChecked ? "Checked" : "Unchecked")

            if isEditing {
                Button("Remove \(item.title)", systemImage: "minus.circle") {
                    save { try store.remove(item.id) }
                }
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)
                .foregroundStyle(theme.caution)
            }
        }
    }

    private func add() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            checklist = try store.add(title)
            title = ""
            message = nil
        } catch {
            message = "Couldn’t add the item. Try again."
        }
    }

    private func reload() {
        do {
            checklist = try store.load()
            message = nil
            canRecover = false
        } catch is DecodingError {
            checklist = nil
            canRecover = true
            message = "Anchor couldn’t read the saved checklist. Starting a new one keeps a copy of the original file."
        } catch {
            checklist = nil
            canRecover = false
            message = "Couldn’t open the checklist."
        }
    }

    private func save(_ change: () throws -> DailyChecklist) {
        do {
            checklist = try change()
            message = nil
        } catch DailyChecklistStore.EditError.dateClosed {
            message = "You can only check items for today and yesterday."
        } catch DailyChecklistStore.EditError.itemRemoved {
            reload()
        } catch {
            message = "Couldn’t save the checklist. Try again."
        }
    }
}
#endif
