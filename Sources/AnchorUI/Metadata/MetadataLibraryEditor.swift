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
    @State private var lastSavedAt: Date?

    private var activeProjects: [Project] { projects.filter { !$0.isArchived } }
    private var archivedProjects: [Project] { projects.filter(\.isArchived) }
    private var activeTags: [SavedTag] { tags.filter { !$0.isArchived } }
    private var archivedTags: [SavedTag] { tags.filter(\.isArchived) }
    private var hasInvalidNames: Bool {
        activeProjects.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || activeTags.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || hasDuplicates(activeProjects.map(\.name))
            || hasDuplicates(activeTags.map(\.name))
    }

    var body: some View {
        NavigationStack {
            Group {
                #if os(macOS)
                macContent
                #else
                phoneContent
                #endif
            }
            .navigationTitle("Projects & tags")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: saveAndDismiss)
                        .disabled(hasInvalidNames)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 820, minHeight: 520, idealHeight: 680)
        #endif
    }

    #if os(macOS)
    private var macContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Label("Reusable context", systemImage: "folder.badge.gearshape")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Projects connect focus time to a larger outcome. Tags add lightweight context across focus, history, and exports.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(theme.negative)
                        .accessibilityIdentifier("anchor.metadata.save-error")
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Space.md) {
                        projectGroup.frame(minWidth: 290)
                        tagGroup.frame(minWidth: 290)
                    }
                    VStack(spacing: Space.md) {
                        projectGroup
                        tagGroup
                    }
                }

                if !archivedProjects.isEmpty || !archivedTags.isEmpty {
                    archivedGroup
                }

                Label(
                    lastSavedAt == nil ? "Renames save with Return or Done" : "Changes saved",
                    systemImage: lastSavedAt == nil ? "return" : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(lastSavedAt == nil ? theme.textTertiary : theme.positive)
                .accessibilityIdentifier("anchor.metadata.save-status")
            }
            .padding(Space.lg)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(theme.canvas)
    }

    private var projectGroup: some View {
        PreferenceGroup(
            "Projects",
            subtitle: "Name the outcomes that focused time belongs to"
        ) {
            creationRow(
                placeholder: "New project",
                text: $newProjectName,
                identifier: "anchor.metadata.new-project",
                buttonIdentifier: "anchor.metadata.add-project",
                save: addProject
            )
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)

            ForEach(activeProjects) { project in
                PreferenceDivider()
                ProjectLibraryRow(project: project, save: saveRenames, archive: { archive(project) })
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.xs)
            }
        }
    }

    private var tagGroup: some View {
        PreferenceGroup(
            "Tags",
            subtitle: "Keep reusable context short and searchable"
        ) {
            creationRow(
                placeholder: "New tag",
                text: $newTagName,
                identifier: "anchor.metadata.new-tag",
                buttonIdentifier: "anchor.metadata.add-tag",
                save: addTag
            )
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)

            ForEach(activeTags) { tag in
                PreferenceDivider()
                TagLibraryRow(tag: tag, save: saveRenames, archive: { archive(tag) })
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.xs)
            }
        }
    }

    private var archivedGroup: some View {
        PreferenceGroup(
            "Archived",
            subtitle: "Restore context without recreating it"
        ) {
            ForEach(archivedProjects) { project in
                archivedRow(project.name, symbol: project.symbolName) { restore(project) }
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.xs)
                if project.id != archivedProjects.last?.id || !archivedTags.isEmpty {
                    PreferenceDivider()
                }
            }
            ForEach(archivedTags) { tag in
                archivedRow(tag.name, symbol: "tag") { restore(tag) }
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.xs)
                if tag.id != archivedTags.last?.id { PreferenceDivider() }
            }
        }
    }
    #endif

    private var phoneContent: some View {
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
                    ProjectLibraryRow(project: project, save: saveRenames, archive: { archive(project) })
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
                    TagLibraryRow(tag: tag, save: saveRenames, archive: { archive(tag) })
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
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(identifier)
                .onSubmit(save)
            Button("Add", systemImage: "plus", action: save)
                .accessibilityIdentifier(buttonIdentifier)
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #if os(macOS)
                .buttonStyle(QuietButtonStyle(expands: false))
                #endif
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
            lastSavedAt = Date()
        } catch {
            context.rollback()
            saveError = "Anchor could not save that library change. Please try again."
        }
    }

    private func saveAndDismiss() {
        guard validateAndSaveRenames() else { return }
        dismiss()
    }

    private func saveRenames() {
        _ = validateAndSaveRenames()
    }

    private func validateAndSaveRenames() -> Bool {
        guard !activeProjects.contains(where: { trimmed($0.name).isEmpty }),
              !activeTags.contains(where: { trimmed($0.name).isEmpty })
        else {
            saveError = "Project and tag names cannot be empty."
            return false
        }
        guard !hasDuplicates(activeProjects.map(\.name)) else {
            saveError = "Each active project needs a different name."
            return false
        }
        guard !hasDuplicates(activeTags.map(\.name)) else {
            saveError = "Each active tag needs a different name."
            return false
        }

        do {
            normalizeNames()
            try context.save()
            saveError = nil
            lastSavedAt = Date()
            return true
        } catch {
            context.rollback()
            saveError = "Anchor could not save that library change. Please try again."
            return false
        }
    }

    private func normalizeNames() {
        for project in activeProjects {
            project.name = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for tag in activeTags {
            tag.name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private func hasDuplicates(_ names: [String]) -> Bool {
        let normalizedNames = names.map(trimmed)
        for (index, name) in normalizedNames.enumerated() {
            if normalizedNames.dropFirst(index + 1).contains(where: { namesMatch(name, $0) }) {
                return true
            }
        }
        return false
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
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
                .help("Archive \(project.name)")
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
                .help("Archive \(tag.name)")
        }
    }
}
#endif
