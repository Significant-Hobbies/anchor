import Foundation
import Testing
@testable import AnchorCore
@testable import AnchorUI

struct ExportFormatTests {
    @Test func workbookUsesLocalCalendarDateAndExtension() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-25T22:19:00Z"))
        let india = try #require(TimeZone(identifier: "Asia/Kolkata"))
        #expect(ExportFormat.workbook.defaultFileName(now: now, timeZone: india) == "Anchor 2026-11-26.xlsx")
    }

    @Test func workbookCarriesPlannerAndDivergenceRows() {
        let block = PlanBlockRecord(id: UUID(), title: "Review drawings", plannedStart: Date(), plannedSeconds: 1800)
        let change = DivergenceRecord(id: UUID(), blockID: block.id, occurredAt: Date(),
                                      kind: .deliberateReplan, evidence: .userConfirmed, note: "Needed feedback")
        let workbook = ExportFormat.workbook.makeData(from: [], plans: [block], divergences: [change])
        #expect(workbook.range(of: Data("Review drawings".utf8)) != nil)
        #expect(workbook.range(of: Data("Needed feedback".utf8)) != nil)
    }
}
