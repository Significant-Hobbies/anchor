// Mac and iPhone screens. The watch is a genuinely different shape — no
// file exporter, no pasteboard, no keyboard shortcuts — so it gets its own
// views in Watch/ rather than a pile of size guards in these.
#if !os(watchOS)
import AnchorCore
import SwiftUI
import UniformTypeIdentifiers

/// Wraps already-rendered bytes so `.fileExporter` works identically on both
/// platforms — one save path instead of an `NSSavePanel` on the Mac and a share
/// sheet on the phone.
public struct ExportDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.spreadsheet, .commaSeparatedText, .json] }
    public static var writableContentTypes: [UTType] { [.spreadsheet, .commaSeparatedText, .json] }

    public var data: Data
    public var contentType: UTType

    public init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    public init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

public extension UTType {
    /// `.spreadsheet` is the generic parent; this is the concrete xlsx type so
    /// Finder and Numbers pick the right handler.
    static let xlsx = UTType(
        exportedAs: "org.openxmlformats.spreadsheetml.sheet",
        conformingTo: .spreadsheet
    )
}

/// What the user is exporting. Kept as one enum so the button, the file name and
/// the bytes can never drift apart.
public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case workbook
    case sessionsCSV
    case distractionsCSV
    case json

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .workbook: "Excel workbook"
        case .sessionsCSV: "Sessions CSV"
        case .distractionsCSV: "Distractions CSV"
        case .json: "JSON"
        }
    }

    public var symbolName: String {
        switch self {
        case .workbook: "tablecells"
        case .sessionsCSV, .distractionsCSV: "doc.plaintext"
        case .json: "curlybraces"
        }
    }

    public var contentType: UTType {
        switch self {
        case .workbook: .xlsx
        case .sessionsCSV, .distractionsCSV: .commaSeparatedText
        case .json: .json
        }
    }

    public func defaultFileName(now: Date = Date()) -> String {
        let stamp = now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        switch self {
        case .workbook: return "Anchor \(stamp)"
        case .sessionsCSV: return "Anchor sessions \(stamp)"
        case .distractionsCSV: return "Anchor distractions \(stamp)"
        case .json: return "Anchor \(stamp)"
        }
    }

    public func makeData(from records: [SessionRecord], now: Date = Date()) -> Data {
        let builder = ExportBuilder()
        switch self {
        case .workbook:
            return builder.xlsxData(from: records, now: now)
        case .sessionsCSV:
            return Data(builder.sessionsCSV(from: records).utf8)
        case .distractionsCSV:
            return Data(builder.distractionsCSV(from: records).utf8)
        case .json:
            return (try? builder.jsonData(from: records, now: now)) ?? Data("{}".utf8)
        }
    }
}
#endif
