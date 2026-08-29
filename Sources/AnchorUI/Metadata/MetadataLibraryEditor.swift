#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

struct MetadataLibraryEditor: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.createdAt) private var projects: [Project]
    @Query(sort: \SavedTag.createdAt) private var tags: [SavedTag]
    @State private var newProjectName = ""
    @State private var newTagName = ""
    @State private var saveError: String?

    private var activeProjects: [Project] { projects.filter { !$0.isArchived } }
    private var archivedProjects: [Project] { projects.filter(\.isArchived) }
    private var activeTags: [SavedTag] { tags.filter { !$0.isArchived } }
    private var archivedTags: [SavedTag] { tags.filter(\.isArchived) }

    var body: some View {
        NavigationStack {
            List {
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.negative)
                        .accessibilityIdentifier("anchor.metadata.save-error")
                }

                Section("Projects") {
                    creationRow(
                        placeholder: "New project",
                        text: $newProjectName,
                        identifier: "anchor.metadata.new-project",
                        buttonIdentifier: "anchor.metadata.add-project",
                        save: addProject
                    )
                    ForEach(activeProjects) { project in
                        ProjectLibraryRow(project: project, save: save, archive: { archive(project) })
                    }
                }

                Section("Saved tags") {
                    creationRow(
                        placeholder: "New tag",
                        text: $newTagName,
                        identifier: "anchor.metadata.new-tag",
                        buttonIdentifier: "anchor.metadata.add-tag",
                        save: addTag
                    )
                    ForEach(activeTags) { tag in
                        TagLibraryRow(tag: tag, save: save, archive: { archive(tag) })
                    }
                }

                if !archivedProjects.isEmpty || !archivedTags.isEmpty {
                    Section("Archived") {
                        ForEach(archivedProjects) { project in
                            archivedRow(project.name, symbol: project.symbolName) { restore(project) }
                        }
                        ForEach(archivedTags) { tag in
                            archivedRow(tag.name, symbol: "tag") { restore(tag) }
                        }
                    }
                }
            }
            .navigationTitle("Projects & tags")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 660, minHeight: 520, idealHeight: 680)
        #endif
    }

    private func creationRow(
        placeholder: String,
        text: Binding<String>,
        identifier: String,
        buttonIdentifier: String,
        save: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Space.sm) {
            TextField(placeholder, text: text)
                .accessibilityIdentifier(identifier)
                .onSubmit(save)
            Button("Add", systemImage: "plus", action: save)
                .accessibilityIdentifier(buttonIdentifier)
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func archivedRow(_ name: String, symbol: String, restore: @escaping () -> Void) -> some View {
        HStack {
            Label(name, systemImage: symbol)
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Button("Restore", action: restore)
                .buttonStyle(QuietButtonStyle(expands: false))
        }
    }

    private func addProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let existing = projects.first(where: { namesMatch($0.name, name) }) {
            existing.archivedAt = nil
            existing.name = name
        } else {
            context.insert(Project(name: name, tintIndex: activeProjects.count % AnchorTheme.goalTints.count))
        }
        newProjectName = ""
        save()
    }

    private func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let existing = tags.first(where: { namesMatch($0.name, name) }) {
            existing.archivedAt = nil
            existing.name = name
        } else {
            context.insert(SavedTag(name: name, tintIndex: activeTags.count % AnchorTheme.goalTints.count))
        }
        newTagName = ""
        save()
    }

    private func archive(_ project: Project) {
        project.archivedAt = Date()
        save()
    }

    private func archive(_ tag: SavedTag) {
        tag.archivedAt = Date()
        save()
    }

    private func restore(_ project: Project) {
        project.archivedAt = nil
        save()
    }

    private func restore(_ tag: SavedTag) {
        tag.archivedAt = nil
        save()
    }

    private func save() {
        do {
            try context.save()
            saveError = nil
        } catch {
            context.rollback()
            saveError = "Anchor could not save that library change. Please try again."
        }
    }

    private func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

private struct ProjectLibraryRow: View {
    @Environment(\.anchorTheme) private var theme
    @Bindable var project: Project
    let save: () -> Void
    let archive: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: project.symbolName)
                .foregroundStyle(AnchorTheme.tint(project.tintIndex))
            TextField("Project name", text: $project.name)
                .onSubmit(save)
                .accessibilityIdentifier("anchor.metadata.project.\(project.id.uuidString)")
            Spacer(minLength: Space.sm)
            Button("Archive", systemImage: "archivebox", action: archive)
                .labelStyle(.iconOnly)
                .foregroundStyle(theme.textTertiary)
                .accessibilityLabel("Archive \(project.name)")
        }
    }
}

private struct TagLibraryRow: View {
    @Environment(\.anchorTheme) private var theme
    @Bindable var tag: SavedTag
    let save: () -> Void
    let archive: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "tag")
                .foregroundStyle(AnchorTheme.tint(tag.tintIndex))
            TextField("Tag name", text: $tag.name)
                .onSubmit(save)
                .accessibilityIdentifier("anchor.metadata.tag.\(tag.id.uuidString)")
            Spacer(minLength: Space.sm)
            Button("Archive", systemImage: "archivebox", action: archive)
                .labelStyle(.iconOnly)
                .foregroundStyle(theme.textTertiary)
                .accessibilityLabel("Archive \(tag.name)")
        }
    }
}
#endif
