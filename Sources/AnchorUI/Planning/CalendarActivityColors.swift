#if !os(watchOS)
import AnchorCore
import SwiftUI

extension EnvironmentValues {
    @Entry var calendarActivityTags: [String: ActivityCategory] = [:]
}

extension ActivityCategory {
    var calendarColor: Color {
        switch self {
        case .meeting: Color(red: 0.718, green: 0.627, blue: 1.0)
        case .fitness: Color(red: 0.451, green: 0.875, blue: 0.69)
        case .meal: Color(red: 1.0, green: 0.78, blue: 0.475)
        case .leisure: Color(red: 1.0, green: 0.612, blue: 0.765)
        case .rest: Color(red: 0.608, green: 0.686, blue: 1.0)
        case .work: Color(red: 0.506, green: 0.773, blue: 1.0)
        case .personal: Color(red: 0.424, green: 0.871, blue: 0.855)
        case .other: Color(red: 0.773, green: 0.788, blue: 0.827)
        }
    }
}
#endif
