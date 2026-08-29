#if DEBUG && !os(watchOS)
import SwiftUI

/// Debug-only access to major sheet content for Anchor's offscreen visual audit.
/// Keeping this in AnchorUI lets the catalog exercise the real internal views
/// without making editing implementation details part of the production API.
public struct AnchorVisualCatalogSheet: View {
    public enum Kind: Sendable {
        case blockEditor
        case habitEditor
        case behaviorProfile
        case metadataLibrary
    }

    private let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    @ViewBuilder
    public var body: some View {
        switch kind {
        case .blockEditor:
            PlanBlockEditor(initialDay: Date(), startsRecurring: false) {}
        case .habitEditor:
            PlanBlockEditor(initialDay: Date(), startsBehaviorHabit: true) {}
        case .behaviorProfile:
            BehaviorProfileEditor()
        case .metadataLibrary:
            MetadataLibraryEditor()
        }
    }
}
#endif
