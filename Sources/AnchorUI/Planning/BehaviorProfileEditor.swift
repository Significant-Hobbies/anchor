#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

struct BehaviorProfileEditor: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [BehaviorProfile]
    @State private var patterns: Set<BehaviorPattern> = []
    @State private var directions: Set<LifeDirection> = []
    @State private var profile: BehaviorProfile?
    @State private var didSave = false
    @State private var saveError: String?
    @State private var showsUnsavedConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Time that sometimes slips away")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text("Intentional enjoyment remains yours. Choose only the patterns you want Anchor to help you notice.")
                            .font(.body)
                            .foregroundStyle(theme.textSecondary)
                    }
                    LazyVGrid(columns: patternColumns, spacing: Space.sm) {
                        ForEach(BehaviorPattern.allCases, id: \.self) { pattern in
                            BehavioralArtworkTile(
                                pattern: pattern,
                                title: pattern.label,
                                isSelected: patterns.contains(pattern)
                            ) { toggle(pattern) }
                        }
                    }

                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("What you want to make room for")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text("Anchor uses these only to suggest evidence-linked replacements you can accept or ignore.")
                            .font(.body)
                            .foregroundStyle(theme.textSecondary)
                    }
                    LazyVGrid(columns: directionColumns, spacing: Space.sm) {
                        ForEach(LifeDirection.allCases, id: \.self) { direction in
                            BehavioralArtworkTile(
                                direction: direction,
                                title: direction.label,
                                isSelected: directions.contains(direction)
                            ) { toggle(direction) }
                        }
                    }

                }
                .padding(Space.lg)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(theme.canvas)
            .navigationTitle("Patterns and replacements")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: Space.md) {
                    saveStatus
                    Spacer(minLength: 0)
                    Button("Done") { close() }
                        .buttonStyle(PrimaryButtonStyle(expands: false))
                }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.sm)
                .background(.bar)
            }
            .onAppear {
                profile = profiles.first
                patterns = profile?.selectedPatterns ?? []
                directions = profile?.desiredDirections ?? []
            }
            .interactiveDismissDisabled(saveError != nil)
            .confirmationDialog(
                "These changes were not saved",
                isPresented: $showsUnsavedConfirmation,
                titleVisibility: .visible
            ) {
                Button("Try saving again") { _ = save() }
                Button("Close without saving", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("Try again, or close and leave your previously saved choices unchanged.")
            }
        }
    }

    private var patternColumns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 138, maximum: 280), spacing: Space.sm)]
    }

    private var directionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 150, maximum: 280), spacing: Space.sm)]
    }

    @ViewBuilder
    private var saveStatus: some View {
        if let saveError {
            VStack(alignment: .leading, spacing: Space.xs) {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(theme.negative)
                    .accessibilityIdentifier("anchor.profile.save-error")
                Button("Try saving again") { _ = save() }
                    .buttonStyle(QuietButtonStyle(expands: false))
            }
        } else {
            Label(
                didSave ? "Saved automatically" : "Changes save automatically",
                systemImage: didSave ? "checkmark.circle.fill" : "arrow.trianglehead.2.clockwise.rotate.90"
            )
            .font(.callout.weight(didSave ? .medium : .regular))
            .foregroundStyle(didSave ? theme.positive : theme.textSecondary)
            .accessibilityIdentifier(didSave ? "anchor.profile.saved" : "anchor.profile.autosave")
        }
    }

    private func toggle(_ pattern: BehaviorPattern) {
        if patterns.contains(pattern) { patterns.remove(pattern) } else { patterns.insert(pattern) }
        _ = save()
    }

    private func toggle(_ direction: LifeDirection) {
        if directions.contains(direction) { directions.remove(direction) } else { directions.insert(direction) }
        _ = save()
    }

    private func close() {
        if saveError == nil {
            dismiss()
        } else {
            showsUnsavedConfirmation = true
        }
    }

    private func save() -> Bool {
        let savedProfile: BehaviorProfile
        if let profile {
            savedProfile = profile
        } else if let existing = profiles.first {
            savedProfile = existing
            profile = existing
        } else {
            let created = BehaviorProfile()
            context.insert(created)
            profile = created
            savedProfile = created
        }
        savedProfile.selectedPatterns = patterns
        savedProfile.desiredDirections = directions
        savedProfile.updatedAt = Date()
        do {
            try context.save()
            saveError = nil
            didSave = true
            return true
        } catch {
            saveError = "Anchor could not save these choices. Please try again."
            didSave = false
            return false
        }
    }
}
#endif
