#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

struct BehaviorProfileEditor: View {
    @Environment(\.anchorTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [BehaviorProfile]
    @State private var patterns: Set<BehaviorPattern> = []
    @State private var directions: Set<LifeDirection> = []
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(theme.negative)
                            .accessibilityIdentifier("anchor.profile.save-error")
                    }
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Time that sometimes slips away")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text("Intentional enjoyment remains yours. Choose only the patterns you want Anchor to help you notice.")
                            .font(.body)
                            .foregroundStyle(theme.textSecondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 138, maximum: 190), spacing: Space.sm)], spacing: Space.sm) {
                        ForEach(BehaviorPattern.allCases, id: \.self) { pattern in
                            BehavioralArtworkTile(
                                imageName: pattern.artworkName,
                                title: pattern.label,
                                isSelected: patterns.contains(pattern)
                            ) { toggle(pattern) }
                        }
                    }

                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("What you want to make room for")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text("Anchor uses these only for evidence-linked alternatives you can accept or ignore.")
                            .font(.body)
                            .foregroundStyle(theme.textSecondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: Space.sm)], spacing: Space.sm) {
                        ForEach(LifeDirection.allCases, id: \.self) { direction in
                            BehavioralArtworkTile(
                                imageName: direction.artworkName,
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
            .navigationTitle("Patterns and alternatives")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if save() { dismiss() }
                    }
                }
            }
            .onAppear {
                patterns = profiles.first?.selectedPatterns ?? []
                directions = profiles.first?.desiredDirections ?? []
            }
        }
    }

    private func toggle(_ pattern: BehaviorPattern) {
        if patterns.contains(pattern) { patterns.remove(pattern) } else { patterns.insert(pattern) }
    }

    private func toggle(_ direction: LifeDirection) {
        if directions.contains(direction) { directions.remove(direction) } else { directions.insert(direction) }
    }

    private func save() -> Bool {
        let profile: BehaviorProfile
        if let existing = profiles.first {
            profile = existing
        } else {
            profile = BehaviorProfile()
            context.insert(profile)
        }
        profile.selectedPatterns = patterns
        profile.desiredDirections = directions
        profile.updatedAt = Date()
        do {
            try context.save()
            saveError = nil
            return true
        } catch {
            saveError = "Anchor could not save these choices. Please try again."
            return false
        }
    }
}
#endif
