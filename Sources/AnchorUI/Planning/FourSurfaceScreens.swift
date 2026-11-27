#if !os(watchOS)
import AnchorCore
import SwiftData
import SwiftUI

public struct TodayScreen: View {
    @State private var day = Date()
    private let controller: FocusController
    private let onOpenFocus: () -> Void

    private let calendarCoordinator: CalendarSyncCoordinator?

    public init(controller: FocusController, calendarCoordinator: CalendarSyncCoordinator? = nil, onOpenFocus: @escaping () -> Void) {
        self.calendarCoordinator = calendarCoordinator
        self.controller = controller
        self.onOpenFocus = onOpenFocus
    }

    public var body: some View {
        PlanScreen(controller: controller, calendarCoordinator: calendarCoordinator, day: $day, onOpenFocus: onOpenFocus)
    }
}
#endif
