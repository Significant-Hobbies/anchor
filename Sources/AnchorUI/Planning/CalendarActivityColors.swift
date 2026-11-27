#if !os(watchOS)
import AnchorCore
import SwiftUI

extension EnvironmentValues {
    @Entry var calendarActivityTags: [String: ActivityCategory] = [:]
}

extension ActivityCategory {
    var calendarColor: Color {
        switch self {
        case .meeting: .purple
        case .fitness: .green
        case .meal: .orange
        case .leisure: .pink
        case .rest: .indigo
        case .work: .blue
        case .personal: .teal
        case .other: .gray
        }
    }
}
#endif
