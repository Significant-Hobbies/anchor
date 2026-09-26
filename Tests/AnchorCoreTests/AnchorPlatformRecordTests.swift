#if !os(watchOS)
@testable import AnchorCore
import Foundation
import PersonalSyncKit
import SwiftData
import Testing

@Suite("Personal Platform session contract")
struct AnchorPlatformRecordTests {
    @Test("Distraction mirror payloads never carry note text or keywords")
    func distractionPayloadExcludesPrivateContent() throws {
        let distraction = Distraction(
            note: "PRIVATE NOTE MUST NOT LEAVE",
            session: nil,
            tagIDStrings: ["tag-1"]
        )
        distraction.keywords = ["PRIVATE", "KEYWORD"]
        distraction.kind = .message
        let payload = DistractionPayload(distraction)
        let data = try JSONEncoder().encode(payload)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("PRIVATE"))
        #expect(!json.contains("\"note\""))
        #expect(!json.contains("keywords"))
        #expect(json.contains("\"recordType\":\"distraction\""))
    }

    @Test("Account deletion uses the authenticated Better Auth endpoint")
    func accountDeletionRequest() throws {
        let request = AnchorAccountDeletionRequest.make(
            identityURL: try #require(URL(string: "https://live.significanthobbies.com")),
            bearerToken: "private-token"
        )
        #expect(request.url?.absoluteString == "https://live.significanthobbies.com/api/auth/delete-user")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer private-token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody == Data("{}".utf8))
    }

    @Test("Account deletion reports service failures without exposing credentials")
    func accountDeletionFailure() throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://live.significanthobbies.com/api/auth/delete-user")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        ))
        #expect(throws: AnchorAccountDeletionError.rejected(status: 401, message: "Sign in again")) {
            try AnchorAccountDeletionRequest.validate(
                data: Data(#"{"message":"Sign in again"}"#.utf8),
                response: response
            )
        }
    }

    @Test
    func finishedSessionContainsNoDistractionText() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2026-08-21T06:00:00Z"))
        let end = start.addingTimeInterval(1_800)
        let session = FocusSession(
            goal: nil,
            intent: "Write proposal",
            plannedSeconds: 1_800,
            startedAt: start
        )
        session.bankedSeconds = 1_800
        session.runningSince = nil
        session.endedAt = end
        session.state = .finished
        session.endReason = .abandoned
        session.notes = "Private outcome detail"
        let distraction = Distraction(note: "Private message from a friend", session: session)
        session.distractions = [distraction]

        let payload = AnchorPlatformRecord.encode(session, endedAt: end)
        let json = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)

        guard case let .object(fields) = payload else {
            Issue.record("Expected a Hub record object")
            return
        }

        #expect(json.contains("Write proposal"))
        #expect(json.contains("interruptionCount"))
        #expect(json.contains("1800"))
        #expect(json.contains("abandoned"))
        #expect(!json.contains("Private message"))
        #expect(!json.contains("Private outcome detail"))
        #expect(Set(fields.keys) == [
            "title", "startedAt", "endedAt", "durationSeconds", "outcome", "interruptionCount",
        ])
    }

    @Test
    func paceSessionUsesStableIdentityAndWallClockDates() throws {
        let change = try JSONDecoder().decode(SyncChange.self, from: Data("""
        {"cursor":1,"changeId":"change-1","domain":"anchor","id":"pace-session","operation":"upsert","version":1,"occurredAt":"2026-08-21T06:00:00Z","recordedAt":"2026-08-21T06:30:01Z","originDeviceId":"pace","record":{"title":"Write proposal","startedAt":"2026-08-21T06:00:00Z","endedAt":"2026-08-21T06:30:00Z","durationSeconds":1800,"outcome":"endedEarly","interruptionCount":2}}
        """.utf8))

        let first = try #require(AnchorPlatformRecord.decode(change))
        let second = try #require(AnchorPlatformRecord.decode(change))

        #expect(first.id == second.id)
        #expect(first.intent == "Write proposal")
        #expect(first.state == .finished)
        #expect(first.endReason == .endedEarly)
        #expect(first.focusedSeconds() == 1_800)
    }

    @Test("Remote Hub history does not enter Anchor's planner")
    @MainActor
    func remoteHubHistoryStaysRemoteUntilApproved() async throws {
        let fixture = try SyncFixture()
        defer { fixture.cleanUp() }
        let remoteID = UUID()
        try await fixture.server.enqueueRemote("""
        {"cursor":2,"changeId":"unapproved-remote","domain":"anchor","id":"session-\(remoteID.uuidString.lowercased())","operation":"upsert","version":3,"occurredAt":"2026-09-02T09:00:00Z","recordedAt":"2026-09-02T09:00:01Z","originDeviceId":"other-device","record":{"recordType":"focusSession","id":"\(remoteID.uuidString)","startedAt":"2026-09-02T08:00:00Z","endedAt":"2026-09-02T09:00:00Z","plannedSeconds":3600,"bankedSeconds":3600,"stateRaw":"finished","endReasonRaw":"completed","intent":"Unapproved remote history","notes":"","tagIDStrings":[],"hourlyRate":0,"currencyCode":"USD","computerActiveSeconds":0,"computerAwaySeconds":0}}
        """)
        await fixture.signIn("A")
        await fixture.sync.synchronize()
        // Sign-in alone is not consent to import. Until the owner approves
        // this device's history binding the Hub leg stays gated — no remote
        // row reaches the planner and not even a pull leaves the device.
        #expect(fixture.sync.needsHistoryApproval)
        #expect(fixture.sync.ownershipNotice != nil)
        #expect(try fixture.context.fetch(FetchDescriptor<FocusSession>()).isEmpty)
        #expect(await fixture.server.pulls.isEmpty)
        #expect(await fixture.server.pushes.isEmpty)
        // The approval gate, not a broken transport, held the record back:
        // the same change imports once the owner explicitly approves.
        #expect(await fixture.sync.approveHubHistory())
        await fixture.sync.synchronize()
        #expect(try fixture.context.fetch(FetchDescriptor<FocusSession>()).map(\.id) == [remoteID])
    }
}
#endif
