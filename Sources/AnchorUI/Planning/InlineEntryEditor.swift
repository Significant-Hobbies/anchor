#if !os(watchOS)
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct InlineEntryEditor: View {
    @Environment(\.anchorTheme) private var theme
    @FocusState private var focused: Bool
    let seed: EditorSeed
    @Binding var title: String
    let error: String?
    let save: () -> Void
    let cancel: () -> Void
    let options: (String) -> Void

    #if os(macOS)
    private let actionSize: CGFloat = 24
    #else
    private let actionSize: CGFloat = 44
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Space.xs) {
                #if os(macOS)
                MacEntryTitleField(title: $title, save: save, cancel: cancel)
                    .frame(minHeight: 22)
                #else
                TextField("What will you do?", text: $title)
                    .textFieldStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                #endif
                Button(action: save) { actionIcon("checkmark") }
                    .accessibilityLabel("Save")
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Menu {
                    Button("More options…") { options(title) }
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
        #if !os(macOS)
        .task(id: seed.id) { await Task.yield(); focused = true }
        #endif
    }

    private func actionIcon(_ name: String) -> some View {
        Image(systemName: name)
            .frame(width: actionSize, height: actionSize)
            .contentShape(Rectangle())
    }
}
#if os(macOS)
/// AppKit's field editor receives Escape before the enclosing SwiftUI view.
private struct MacEntryTitleField: NSViewRepresentable {
    @Binding var title: String
    let save: () -> Void
    let cancel: () -> Void

    final class TitleField: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                window.makeFirstResponder(self)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TitleField {
        let field = TitleField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "What will you do?"
        field.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: TitleField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != title { field.stringValue = title }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacEntryTitleField
        init(_ parent: MacEntryTitleField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.title = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            switch command {
            case #selector(NSResponder.cancelOperation(_:)):
                parent.cancel()
            case #selector(NSResponder.insertNewline(_:)):
                guard !textView.hasMarkedText() else { return false }
                parent.title = textView.string
                parent.save()
            default:
                return false
            }
            return true
        }
    }
}
#endif
#endif
