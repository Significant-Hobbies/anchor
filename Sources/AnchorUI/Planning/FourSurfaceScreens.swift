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

public struct HistoryScreen: View {
    @Environment(\.anchorTheme) private var theme
    @State private var section: Section = .day

    @State private var standaloneDay = Date()
    private let day: Binding<Date>?

    public init(section: Section = .day, day: Binding<Date>? = nil) {
        self.day = day
        _section = State(initialValue: section)
    }

    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case day = "Day review"
        case interruptions = "Interruptions"
        case trends = "Insights"
        public var id: String { rawValue }
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("History section", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Space.lg)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.xs)
            .frame(maxWidth: 680)

            switch section {
            case .day: DayReviewScreen(selectedDay: day ?? $standaloneDay)
            case .interruptions: LogScreen()
            case .trends: AnalyticsScreen()
            }
        }
        .background(theme.canvas)
    }
}
#endif
