// Mac and iPhone share the richer metadata editor. The watch stays a remote.
#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

struct ProjectPicker: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    @Binding var selectedID: UUID?
    @State private var isCreating = false
    @State private var newName = ""

    private var activeProjects: [Project] { projects.filter { !$0.isArchived } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            metadataLabel("Project — optional")

            FlowRow(spacing: Space.xxs) {
                Button {
                    selectedID = nil
                } label: {
                    Chip("No project", symbol: "folder", isSelected: selectedID == nil)
                }
                .buttonStyle(.plain)

                ForEach(activeProjects) { project in
                    Button {
                        selectedID = project.id
                    } label: {
                        Chip(
                            project.name,
                            symbol: project.symbolName,
                            tint: AnchorTheme.tint(project.tintIndex),
                            isSelected: selectedID == project.id
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    isCreating.toggle()
                } label: {
                    Chip("New project", symbol: "plus")
                }
                .buttonStyle(.plain)
            }

            if isCreating {
                creationRow(
                    placeholder: "Anchor",
                    text: $newName,
                    save: saveProject
                )
            }
        }
        .animation(Motion.snappy, value: isCreating)
    }

    private func saveProject() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = activeProjects.first(where: {
            $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            selectedID = existing.id
        } else {
            let project = Project(
                name: trimmed,
                tintIndex: activeProjects.count % AnchorTheme.goalTints.count
            )
            context.insert(project)
            try? context.save()
            selectedID = project.id
        }
        newName = ""
        isCreating = false
    }

    private func metadataLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(theme.textTertiary)
    }

    private func creationRow(
        placeholder: String,
        text: Binding<String>,
        save: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Space.xs) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs)
                .background(theme.surfaceRaised, in: .rect(cornerRadius: Radius.sm))
                .onSubmit(save)
            Button("Save", action: save)
                .buttonStyle(QuietButtonStyle(expands: false))
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

struct SavedTagPicker: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedTag.createdAt) private var tags: [SavedTag]

    @Binding var selectedIDs: [String]
    @State private var isCreating = false
    @State private var newName = ""

    private var activeTags: [SavedTag] { tags.filter { !$0.isArchived } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("TAGS — OPTIONAL, SAVED FOR REUSE")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(theme.textTertiary)

            FlowRow(spacing: Space.xxs) {
                ForEach(activeTags) { tag in
                    Button {
                        toggle(tag.storageID)
                    } label: {
                        Chip(
                            tag.name,
                            symbol: "tag",
                            tint: AnchorTheme.tint(tag.tintIndex),
                            isSelected: selectedIDs.contains(tag.storageID)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    isCreating.toggle()
                } label: {
                    Chip("New tag", symbol: "plus")
                }
                .buttonStyle(.plain)
            }

            if isCreating {
                HStack(spacing: Space.xs) {
                    TextField("deep work", text: $newName)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, Space.xs)
                        .background(theme.surfaceRaised, in: .rect(cornerRadius: Radius.sm))
                        .onSubmit(saveTag)
                    Button("Save", action: saveTag)
                        .buttonStyle(QuietButtonStyle(expands: false))
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .animation(Motion.snappy, value: isCreating)
    }

    private func toggle(_ id: String) {
        if let index = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(id)
        }
    }

    private func saveTag() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let tag: SavedTag
        if let existing = activeTags.first(where: {
            $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            tag = existing
        } else {
            tag = SavedTag(
                name: trimmed,
                tintIndex: activeTags.count % AnchorTheme.goalTints.count
            )
            context.insert(tag)
            try? context.save()
        }
        if !selectedIDs.contains(tag.storageID) { selectedIDs.append(tag.storageID) }
        newName = ""
        isCreating = false
    }
}
#endif
