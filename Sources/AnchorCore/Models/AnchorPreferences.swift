import Foundation
import SwiftData

/// The appearance of every full Anchor app. `system` deliberately follows each
/// device; explicit light or dark choices travel with the private CloudKit store.
public enum AnchorAppearance: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// A CloudKit-safe owner preference. Multiple records are tolerated because
/// two offline devices may each create the first record; the newest update wins.
@Model
public final class AnchorPreferences {
    public var id: UUID = UUID()
    public var appearanceRaw: String = AnchorAppearance.dark.rawValue
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        appearance: AnchorAppearance = .dark,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.appearance = appearance
        self.updatedAt = updatedAt
    }

    public var appearance: AnchorAppearance {
        get { AnchorAppearance(rawValue: appearanceRaw) ?? .dark }
        set { appearanceRaw = newValue.rawValue }
    }
}

/// One deterministic policy is used by Settings and every platform root.
public enum AnchorPreferencesPolicy {
    public static func latest(in records: [AnchorPreferences]) -> AnchorPreferences? {
        records.max { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                lhs.id.uuidString < rhs.id.uuidString
            } else {
                lhs.updatedAt < rhs.updatedAt
            }
        }
    }

    public static func appearance(in records: [AnchorPreferences]) -> AnchorAppearance {
        latest(in: records)?.appearance ?? .dark
    }
}
