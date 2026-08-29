#if !os(watchOS)
import AnchorCore
import Foundation
import PersonalSyncKit
import Testing

@Suite("Personal Platform session contract")
struct AnchorPlatformRecordTests {
    @Test("Remote Hub history does not enter Anchor's planner")
    func hubIsOutboundOnly() {
        #expect(!AnchorPlatformSync.importsRemoteSessions)
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
}
#endif
