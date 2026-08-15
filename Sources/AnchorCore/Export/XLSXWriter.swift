import Foundation

/// A real .xlsx workbook, written from scratch.
///
/// Uses inline strings rather than a shared-string table (simpler, and the size
/// difference is irrelevant at focus-log scale) and a small fixed style table so
/// dates, percentages and durations arrive in Excel and Numbers already
/// formatted rather than as bare numbers the user has to fix by hand.
public struct Spreadsheet: Sendable {
    public struct Sheet: Sendable {
        public var name: String
        public var columns: [Column]
        public var rows: [[Cell]]

        public init(name: String, columns: [Column], rows: [[Cell]]) {
            self.name = name
            self.columns = columns
            self.rows = rows
        }
    }

    public struct Column: Sendable {
        public var title: String
        public var width: Double

        public init(_ title: String, width: Double = 16) {
            self.title = title
            self.width = width
        }
    }

    public enum Cell: Sendable {
        case text(String)
        case number(Double)
        case integer(Int)
        case date(Date)
        /// 0...1, rendered as a percentage.
        case percent(Double)
        case blank

        public static func optionalText(_ value: String?) -> Cell {
            value.map(Cell.text) ?? .blank
        }
    }

    public var sheets: [Sheet]

    public init(sheets: [Sheet]) {
        self.sheets = sheets
    }

    /// Serialise to .xlsx bytes.
    public func xlsxData(modified: Date = Date()) -> Data {
        var zip = ZipWriter(modified: modified)
        let names = Self.uniqueSheetNames(sheets.map(\.name))

        zip.add(path: "[Content_Types].xml", contents: contentTypes())
        zip.add(path: "_rels/.rels", contents: rootRelationships())
        zip.add(path: "xl/workbook.xml", contents: workbook(names: names))
        zip.add(path: "xl/_rels/workbook.xml.rels", contents: workbookRelationships())
        zip.add(path: "xl/styles.xml", contents: Self.styles)
        for (index, sheet) in sheets.enumerated() {
            zip.add(path: "xl/worksheets/sheet\(index + 1).xml", contents: Self.worksheet(sheet))
        }
        return zip.finalize()
    }

    // MARK: - Package parts

    private func contentTypes() -> String {
        let overrides = sheets.indices.map {
            #"<Override PartName="/xl/worksheets/sheet\#($0 + 1).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
        \(overrides)</Types>
        """
    }

    private func rootRelationships() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
        </Relationships>
        """
    }

    private func workbook(names: [String]) -> String {
        let entries = names.enumerated().map { index, name in
            #"<sheet name="\#(Self.escape(name))" sheetId="\#(index + 1)" r:id="rId\#(index + 1)"/>"#
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <sheets>\(entries)</sheets></workbook>
        """
    }

    private func workbookRelationships() -> String {
        var entries = sheets.indices.map { index in
            #"<Relationship Id="rId\#(index + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\#(index + 1).xml"/>"#
        }.joined()
        entries += #"<Relationship Id="rId\#(sheets.count + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>"#
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(entries)</Relationships>
        """
    }

    /// Style indices used by ``styleIndex(for:)``:
    /// 0 default · 1 bold header · 2 date-time · 3 percent · 4 two-decimal number.
    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
    <fonts count="2">\
    <font><sz val="12"/><name val="Calibri"/></font>\
    <font><b/><sz val="12"/><name val="Calibri"/></font>\
    </fonts>\
    <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
    <cellXfs count="5">\
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>\
    <xf numFmtId="22" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="10" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="2" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    </cellXfs>\
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>\
    </styleSheet>
    """

    private static func worksheet(_ sheet: Sheet) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        """

        if !sheet.columns.isEmpty {
            let cols = sheet.columns.enumerated().map { index, column in
                #"<col min="\#(index + 1)" max="\#(index + 1)" width="\#(column.width)" customWidth="1"/>"#
            }.joined()
            xml += "<cols>\(cols)</cols>"
        }

        xml += "<sheetData>"

        // Header row, frozen visually by being bold — a real freeze pane needs
        // sheetViews, which is more XML than a header row is worth here.
        if !sheet.columns.isEmpty {
            let cells = sheet.columns.enumerated().map { index, column in
                inlineString(column.title, reference: "\(columnName(index))1", style: 1)
            }.joined()
            xml += #"<row r="1">\#(cells)</row>"#
        }

        for (rowIndex, row) in sheet.rows.enumerated() {
            let number = rowIndex + 2
            let cells = row.enumerated().compactMap { columnIndex, cell in
                encode(cell, reference: "\(columnName(columnIndex))\(number)")
            }.joined()
            xml += #"<row r="\#(number)">\#(cells)</row>"#
        }

        xml += "</sheetData></worksheet>"
        return xml
    }

    private static func encode(_ cell: Cell, reference: String) -> String? {
        switch cell {
        case .blank:
            return nil
        case .text(let value):
            return inlineString(value, reference: reference, style: 0)
        case .number(let value):
            guard value.isFinite else { return nil }
            return #"<c r="\#(reference)" s="4"><v>\#(value)</v></c>"#
        case .integer(let value):
            return #"<c r="\#(reference)"><v>\#(value)</v></c>"#
        case .percent(let value):
            guard value.isFinite else { return nil }
            return #"<c r="\#(reference)" s="3"><v>\#(value)</v></c>"#
        case .date(let value):
            return #"<c r="\#(reference)" s="2"><v>\#(excelSerial(value))</v></c>"#
        }
    }

    private static func inlineString(_ value: String, reference: String, style: Int) -> String {
        let styleAttribute = style == 0 ? "" : #" s="\#(style)""#
        return #"<c r="\#(reference)"\#(styleAttribute) t="inlineStr"><is><t xml:space="preserve">\#(escape(value))</t></is></c>"#
    }

    /// Excel counts days from 1899-12-30 (the offset absorbs its 1900 leap-year bug).
    static func excelSerial(_ date: Date) -> Double {
        var components = DateComponents()
        components.year = 1899
        components.month = 12
        components.day = 30
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let epoch = calendar.date(from: components) else { return 0 }
        // Shift by the local offset so the timestamp reads as local time in the sheet.
        let offset = Double(TimeZone.current.secondsFromGMT(for: date))
        return (date.timeIntervalSince(epoch) + offset) / 86400
    }

    /// 0 -> A, 25 -> Z, 26 -> AA.
    static func columnName(_ index: Int) -> String {
        var value = index
        var name = ""
        repeat {
            name = String(UnicodeScalar(UInt8(65 + value % 26))) + name
            value = value / 26 - 1
        } while value >= 0
        return name
    }

    /// Excel rejects duplicate sheet names, names over 31 characters, and a set
    /// of reserved punctuation — so normalise rather than produce a corrupt file.
    static func uniqueSheetNames(_ names: [String]) -> [String] {
        var used = Set<String>()
        return names.map { raw in
            var name = raw.filter { !"[]:*?/\\".contains($0) }
            if name.isEmpty { name = "Sheet" }
            if name.count > 31 { name = String(name.prefix(31)) }
            var candidate = name
            var suffix = 2
            while !used.insert(candidate.lowercased()).inserted {
                let trimmed = String(name.prefix(31 - "\(suffix)".count - 1))
                candidate = "\(trimmed) \(suffix)"
                suffix += 1
            }
            return candidate
        }
    }

    static func escape(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            case "\"": output += "&quot;"
            case "'": output += "&apos;"
            default:
                // XML 1.0 forbids most control characters outright.
                if let scalar = character.unicodeScalars.first,
                   scalar.value < 0x20,
                   scalar != "\n", scalar != "\t", scalar != "\r" {
                    continue
                }
                output.append(character)
            }
        }
        return output
    }
}
