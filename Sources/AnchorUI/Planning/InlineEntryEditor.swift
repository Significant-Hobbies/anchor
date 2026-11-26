#if !os(watchOS)
import SwiftUI

struct InlineEntryEditor: View {
    @Environment(\.anchorTheme) private var theme
    @FocusState private var focused: Bool
    let seed: EditorSeed
    @Binding var title: String
    let error: String?
    let save: () -> Void
    let cancel: () -> Void
    let options: () -> Void

    #if os(macOS)
    private let actionSize: CGFloat = 24
    #else
    private let actionSize: CGFloat = 44
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Space.xs) {
                TextField("What will you do?", text: $title)
                    .textFieldStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                Button(action: save) { actionIcon("checkmark") }
                    .accessibilityLabel("Save")
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Menu {
                    Button("More options…", action: options)
                    Button("Cancel", action: cancel)
                } label: { actionIcon("ellipsis.circle") }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Entry actions")
            }
            Text("\(seed.start.formatted(date: .omitted, time: .shortened)) – \(seed.start.addingTimeInterval(Double(seed.minutes * 60)).formatted(date: .omitted, time: .shortened))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.textSecondary)
            if let error {
                Text(error).font(.caption).foregroundStyle(theme.negative)
            } else if seed.dayIsFull {
                Text("Overlaps your schedule").font(.caption).foregroundStyle(theme.caution)
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .buttonStyle(.borderless)
        .foregroundStyle(theme.textPrimary)
        .background(theme.surfaceRaised, in: .rect(cornerRadius: Radius.sm))
        .overlay(alignment: .leading) { Capsule().fill(theme.accent).frame(width: 3).padding(.vertical, 4) }
        .overlay { RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(theme.accent.opacity(0.6)) }
        .task(id: seed.id) { await Task.yield(); focused = true }
        #if os(macOS)
        .onExitCommand(perform: cancel)
        #endif
    }

    private func actionIcon(_ name: String) -> some View {
        Image(systemName: name)
            .frame(width: actionSize, height: actionSize)
            .contentShape(Rectangle())
    }
}
#endif
