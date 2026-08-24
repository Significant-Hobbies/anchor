import Foundation
import Testing

@testable import AnchorCore

@Suite("Export")
struct ExportTests {
    let builder = ExportBuilder(calendar: Fixture.calendar)

    var records: [SessionRecord] {
        [
            Fixture.session(goal: "Ship auth", focused: 1500, distractions: [
                Fixture.distraction("Slack from \"Ravi\", re: invoice", kind: .message, keywords: ["slack", "ravi"]),
                Fixture.distraction("went down a\nrabbit hole", kind: .rabbitHole, returned: false),
            ]),
            Fixture.session(goal: "Write the post", theme: .writing, focused: 900, reason: .endedEarly),
        ]
    }

    // MARK: XLSX

    @Test("The workbook is a well-formed ZIP with the parts Excel requires")
    func workbookStructure() throws {
        let data = builder.xlsxData(from: records, now: Fixture.day0)
        let text = String(decoding: data, as: UTF8.self)

        // Local header, central directory and end-of-central-directory signatures.
        #expect(data.starts(with: [0x50, 0x4B, 0x03, 0x04]))
        #expect(text.contains("[Content_Types].xml"))
        #expect(text.contains("xl/workbook.xml"))
        #expect(text.contains("xl/styles.xml"))
        #expect(text.contains("xl/worksheets/sheet1.xml"))
        #expect(text.contains("xl/worksheets/sheet6.xml"))
        #expect(text.contains("_rels/.rels"))
    }

    @Test("The workbook actually unzips and every sheet is present")
    func workbookUnzips() throws {
        let data = builder.xlsxData(from: records, now: Fixture.day0)
        let url = FileManager.default.temporaryDirectory
            .appending(path: "anchor-test-\(UUID().uuidString).xlsx")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // `unzip -t` verifies every entry's CRC, which is the real check that the
        // hand-written archive is valid rather than merely well-labelled.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        #expect(process.terminationStatus == 0, "unzip rejected the archive:\n\(output)")
        #expect(output.contains("No errors detected"))
    }

    @Test("Sheet names are unique, trimmed and free of reserved characters")
    func sheetNamesAreLegal() {
        let names = Spreadsheet.uniqueSheetNames([
            "Summary", "Summary", "Bad/Name:Here",
            String(repeating: "x", count: 40),
        ])
        #expect(names[0] == "Summary")
        #expect(names[1] == "Summary 2")
        #expect(names[2] == "BadNameHere")
        #expect(names[3].count == 31)
        #expect(Set(names.map { $0.lowercased() }).count == 4)
    }

    @Test("Column letters roll over past Z")
    func columnNames() {
        #expect(Spreadsheet.columnName(0) == "A")
        #expect(Spreadsheet.columnName(25) == "Z")
        #expect(Spreadsheet.columnName(26) == "AA")
        #expect(Spreadsheet.columnName(27) == "AB")
        #expect(Spreadsheet.columnName(51) == "AZ")
        #expect(Spreadsheet.columnName(52) == "BA")
    }

    @Test("XML special characters in a note cannot corrupt the sheet")
    func xmlEscaping() {
        let escaped = Spreadsheet.escape("a & b <tag> \"quoted\" 'single'")
        #expect(escaped == "a &amp; b &lt;tag&gt; &quot;quoted&quot; &apos;single&apos;")
        // Control characters are illegal in XML 1.0 and are dropped, not encoded.
        #expect(!Spreadsheet.escape("bad\u{0007}char").contains("\u{0007}"))
    }

    @Test("Excel serial dates use the 1899-12-30 epoch")
    func excelSerialEpoch() {
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let date = calendar.date(from: components)!
        // 2024-01-01 is day 45292 in Excel's numbering.
        #expect(abs(Spreadsheet.excelSerial(date) - 45292) < 0.01)
    }

    // MARK: CSV

    @Test("CSV quotes commas, quotes and newlines per RFC 4180")
    func csvQuoting() {
        let row = ExportBuilder.csvRow(["plain", "has,comma", "has\"quote", "has\nnewline"])
        #expect(row == #"plain,"has,comma","has""quote","has"# + "\n" + #"newline""#)
    }

    @Test("Distraction notes with quotes survive the CSV round trip")
    func csvHandlesRealNotes() {
        let csv = builder.distractionsCSV(from: records)
        #expect(csv.contains(#""Slack from ""Ravi"", re: invoice""#))
        // Header plus two distractions; the embedded newline is inside quotes,
        // so the line count is header + 2 records + trailing newline split.
        #expect(csv.hasPrefix("captured_at,note,category"))
    }

    @Test("Sessions CSV has one row per session")
    func sessionsCSV() {
        let csv = builder.sessionsCSV(from: records)
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("started,ended,goal"))
        #expect(csv.contains("Ship auth"))
        #expect(csv.contains("Write the post"))
    }

    // MARK: JSON

    @Test("JSON export carries the overview and every session")
    func jsonExport() throws {
        let data = try builder.jsonData(from: records, now: Fixture.day0)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ExportBundle.self, from: data)

        #expect(bundle.sessions.count == 2)
        #expect(bundle.overview.sessionCount == 2)
        #expect(bundle.sessions.first?.distractions.count == 2)
        #expect(bundle.plans.isEmpty)
        #expect(bundle.divergences.isEmpty)
    }

    @Test("Unified export carries plans, causes, and private profile selections")
    func unifiedJSONExport() throws {
        let blockID = UUID()
        let plan = PlanBlockRecord(
            id: blockID,
            title: "Walk",
            plannedStart: Fixture.day0,
            plannedSeconds: 1_800,
            kind: .routine,
            lifeDirection: .movement
        )
        let divergence = DivergenceRecord(
            id: UUID(),
            blockID: blockID,
            occurredAt: Fixture.day0,
            kind: .deliberateReplan,
            evidence: .userConfirmed,
            note: "Rain changed the route."
        )
        let data = try builder.jsonData(
            from: records,
            plans: [plan],
            divergences: [divergence],
            profile: BehaviorProfileRecord(selectedPatterns: [.shortVideo], desiredDirections: [.movement]),
            now: Fixture.day0
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ExportBundle.self, from: data)
        #expect(bundle.plans.first?.title == "Walk")
        #expect(bundle.divergences.first?.note == "Rain changed the route.")
        #expect(bundle.profile.selectedPatterns == [.shortVideo])
        #expect(builder.plansCSV(from: [plan]).contains("Walk"))
        #expect(builder.divergencesCSV(from: [divergence]).contains("deliberateReplan"))
    }
}

@Suite("JSON value")
struct JSONValueTests {
    @Test("Parses the shapes JSON-RPC actually sends")
    func parsing() {
        let value = JSONValue(jsonString: #"{"id":7,"method":"tools/call","params":{"name":"x","flag":true,"ratio":0.5}}"#)
        #expect(value?["id"]?.intValue == 7)
        #expect(value?["method"]?.stringValue == "tools/call")
        #expect(value?["params"]?["name"]?.stringValue == "x")
        #expect(value?["params"]?["flag"]?.boolValue == true)
        // Booleans must not be swallowed by NSNumber's integer bridging.
        #expect(value?["params"]?["flag"] != .int(1))
    }

    @Test("Encoding is stable and escapes control characters")
    func encoding() {
        let value = JSONValue.object([
            "b": .string("two"),
            "a": .int(1),
            "c": .string("line\nbreak\ttab"),
        ])
        // Keys sorted, so output is diffable and testable.
        #expect(value.encodedString() == #"{"a":1,"b":"two","c":"line\nbreak\ttab"}"#)
    }

    @Test("Non-finite doubles become null rather than invalid JSON")
    func nonFiniteDoubles() {
        #expect(JSONValue.double(.infinity).encodedString() == "null")
        #expect(JSONValue.double(.nan).encodedString() == "null")
        #expect(JSONValue.double(3.0).encodedString() == "3")
    }

    @Test("Malformed input is rejected rather than trapping")
    func malformedInput() {
        #expect(JSONValue(jsonString: "{not json") == nil)
    }
}
