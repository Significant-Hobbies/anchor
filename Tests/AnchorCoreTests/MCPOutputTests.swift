import Foundation
import SwiftData
import Testing

@testable import AnchorCore

@MainActor
@Suite("MCP output")
struct MCPOutputTests {
    @Test("Legacy rates stay inert across session JSON and MCP queries")
    func legacyRatesAreNotReported() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "anchor-mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Anchor.store")
        let container = try AnchorStore.makeContainer(kind: .localOnly, url: storeURL)
        let context = ModelContext(container)
        let project = Project(name: "Anchor", hourlyRate: 125, currencyCode: "EUR")
        let tag = SavedTag(name: "deep")
        let session = FocusSession(
            goal: nil, intent: "Ship", project: project, tagIDStrings: [tag.storageID],
            hourlyRate: 125, currencyCode: "EUR", plannedSeconds: 1800, startedAt: Fixture.day0
        )
        session.state = .finished
        session.endReason = .completed
        session.endedAt = Fixture.day0.addingTimeInterval(1800)
        session.runningSince = nil
        session.bankedSeconds = 1800
        session.computerActiveSeconds = 1200
        session.computerAwaySeconds = 600
        context.insert(project)
        context.insert(tag)
        context.insert(session)
        context.insert(MachineActivityDay(day: Fixture.day0, activeSeconds: 3600, trackedSeconds: 1200))
        try context.save()

        let json = try ExportBuilder().jsonData(from: context.sessionRecords(), now: Fixture.day0)
        let exported = try #require(JSONValue(jsonString: String(decoding: json, as: UTF8.self)))
        let exportedSession = try #require(exported["sessions"]?.arrayValue?.first)
        #expect(exportedSession["projectTitle"]?.stringValue == "Anchor")
        #expect(exportedSession["computerActiveSeconds"]?.doubleValue == 1200)
        #expect(exportedSession["hourlyRate"] == nil)
        #expect(exportedSession["currencyCode"] == nil)

        // Exercise the shipped stdio transport against a separate, disposable store.
        let executable = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: ".build/debug/anchor-mcp")
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
        let process = Process()
        process.executableURL = executable
        var environment = ProcessInfo.processInfo.environment
        environment["ANCHOR_STORE_PATH"] = storeURL.path
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        let errors = directory.appending(path: "stderr.log")
        _ = FileManager.default.createFile(atPath: errors.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errors)
        defer { try? errorHandle.close() }
        process.standardError = errorHandle
        try process.run()
        let requests = ["list_sessions", "work_patterns", "machine_presence"].enumerated().map { index, tool in
            JSONValue.object([
                "jsonrpc": .string("2.0"), "id": .int(index), "method": .string("tools/call"),
                "params": .object(["name": .string(tool), "arguments": .object([:])]),
            ]).encodedString()
        }.joined(separator: "\n") + "\n"
        try input.fileHandleForWriting.write(contentsOf: Data(requests.utf8))
        try input.fileHandleForWriting.close()
        let responseData = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let replies = String(decoding: responseData, as: UTF8.self).split(separator: "\n")
        #expect(replies.count == 3)
        let payloads = try replies.map { line -> JSONValue in
            let reply = try #require(JSONValue(jsonString: String(line)))
            #expect(reply["result"]?["isError"]?.boolValue == false)
            let text = try #require(reply["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue)
            return try #require(JSONValue(jsonString: text))
        }
        let listedSession = try #require(payloads[0].arrayValue?.first)
        #expect(listedSession["project"]?.stringValue == "Anchor")
        #expect(listedSession["tags"]?.arrayValue == [.string("deep")])
        #expect(listedSession["focusedMinutes"]?.doubleValue == 30)
        #expect(listedSession["computerActiveMinutes"]?.doubleValue == 20)
        #expect(listedSession["computerAwayMinutes"]?.doubleValue == 10)
        #expect(listedSession["hourlyRate"] == nil)
        #expect(listedSession["currency"] == nil)
        #expect(listedSession["trackedValue"] == nil)
        #expect(payloads[1]["billing"] == nil)
        #expect(payloads[1]["projects"]?.arrayValue?.first?["name"]?.stringValue == "Anchor")
        #expect(payloads[1]["tags"]?.arrayValue?.first?["name"]?.stringValue == "deep")
        #expect(payloads[2]["machineActiveHours"]?.doubleValue == 1)
        #expect(payloads[2]["loggedActiveHours"]?.doubleValue == 0.3333)
        #expect(session.hourlyRate == 125)
        #expect(project.currencyCode == "EUR")
    }
}

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        if case .array(let values) = self { return values }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value): value
        case .int(let value): Double(value)
        default: nil
        }
    }
}
