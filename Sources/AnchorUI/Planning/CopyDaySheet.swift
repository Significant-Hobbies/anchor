#if !os(watchOS)
import SwiftUI

struct CopyDaySheet: View {
    @Environment(\.dismiss) private var dismiss
    let sourceDay: Date
    let entryCount: Int
    let copy: (Date) -> String?
    @State private var destination: Date
    @State private var error: String?

    init(sourceDay: Date, entryCount: Int, copy: @escaping (Date) -> String?) {
        self.sourceDay = sourceDay
        self.entryCount = entryCount
        self.copy = copy
        _destination = State(initialValue: Calendar.current.date(byAdding: .day, value: 1, to: sourceDay) ?? sourceDay)
    }

    var body: some View {
        NavigationStack {
            Form {
                Text("Copy \(entryCount) entries from \(sourceDay.formatted(date: .abbreviated, time: .omitted)).")
                DatePicker("To day", selection: $destination, displayedComponents: .date)
                Text("Keeps times and projects. Copies start unfinished. Existing entries on that day stay in place.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Copy day")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy entries") {
                        error = copy(destination)
                        if error == nil { dismiss() }
                    }
                    .disabled(Calendar.current.isDate(sourceDay, inSameDayAs: destination))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 260)
        #endif
    }
}
#endif
