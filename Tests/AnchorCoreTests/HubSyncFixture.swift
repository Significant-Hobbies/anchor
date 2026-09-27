#if !os(watchOS)
@testable import AnchorCore
import Foundation
import PersonalSyncKit
import SwiftData
import Synchronization
import Testing

@MainActor
final class SyncFixture {
    let directory = FileManager.default.temporaryDirectory.appending(path: "anchor-account-sync-\(UUID())")
    let suite = "anchor-account-sync-\(UUID())"
    let tokens = FixtureTokens()
    let server = FixtureHub()
    let container: ModelContainer
    let context: ModelContext
    let origin: URL
    let transport: URLSession
    let identity: PersonalIdentityClient
    let defaults: UserDefaults
    let receipts: HubSyncReceiptStore
    lazy var sync = makeSync()

    init(storeURL: URL? = nil) throws {
        if let storeURL {
            container = try AnchorStore.makeContainer(kind: .localOnly, url: storeURL)
        } else {
            container = try AnchorStore.makeContainer(kind: .inMemory)
        }
        context = ModelContext(container)
        origin = URL(string: "https://\(UUID().uuidString.lowercased()).invalid")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        transport = URLSession(configuration: configuration)
        identity = PersonalIdentityClient(baseURL: origin, session: transport, tokenStore: tokens)
        defaults = UserDefaults(suiteName: suite)!
        receipts = HubSyncReceiptStore(defaults: defaults)
        FixtureProtocol.servers.withLock { $0[origin.host!] = server }
    }

    func makeSync() -> AnchorPlatformSync {
        AnchorPlatformSync(
            context: context, identity: identity, supportDirectory: directory,
            deviceId: "synthetic-device", receiptStore: receipts,
            transport: transport, platformURL: origin, identityOrigin: origin,
            observeLocalSaves: false
        )
    }

    func signIn(_ token: String) async {
        await tokens.save(token)
        await sync.account?.restore()
        #expect(sync.account?.isSignedIn == true)
    }

    @discardableResult
    func addSession(_ title: String) -> FocusSession {
        let session = FocusSession(goal: nil, intent: title, plannedSeconds: 60)
        session.endedAt = session.startedAt.addingTimeInterval(60)
        session.bankedSeconds = 60
        session.runningSince = nil
        session.state = .finished
        session.endReason = .completed
        session.notes = "synthetic session outcome note"
        let distraction = Distraction(note: "PRIVATE SYNTHETIC NOTE MUST NOT LEAVE", session: session)
        distraction.keywords = ["PRIVATE", "SYNTHETIC"]
        context.insert(distraction)
        context.insert(session)
        return session
    }

    func cleanUp() {
        transport.invalidateAndCancel()
        FixtureProtocol.servers.withLock { _ = $0.removeValue(forKey: origin.host!) }
        defaults.removePersistentDomain(forName: suite)
        if FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

actor FixtureTokens: PersonalBearerTokenStore {
    var token: String?
    func load() -> String? { token }
    func save(_ token: String) { self.token = token }
    func delete() { token = nil }
}

actor FixtureHub {
    struct Push: Sendable { let token: String; let mutations: [SyncMutation] }
    struct Pull: Sendable { let token: String; let cursor: Int }
    struct Reply: Sendable { let status: Int; let data: Data }
    private(set) var identityRequests = 0
    private(set) var deletions: [String] = []
    private(set) var pushes: [Push] = []
    private(set) var pulls: [Pull] = []
    var remoteChanges: [[String: Any]] = []
    func enqueueRemote(_ json: String) throws {
        let change = try JSONSerialization.jsonObject(with: Data(json.utf8))
        guard let change = change as? [String: Any] else { throw URLError(.cannotParseResponse) }
        remoteChanges.append(change)
    }
    func removeRemote(id: String) { remoteChanges.removeAll { $0["id"] as? String == id } }
    private var failures: Set<String> = []
    private var holds: Set<String> = []
    private var held: [String: CheckedContinuation<Int, Never>] = [:]
    private var waiting: [String: CheckedContinuation<Void, Never>] = [:]
    func failPushes(for token: String) { failures.insert(token) }
    func allowPushes(for token: String) { failures.remove(token) }
    func holdPushes(for token: String) { holds.insert(token) }
    func stopHoldingPushes(for token: String) { holds.remove(token) }
    func waitUntilHeld(_ token: String) async {
        if held[token] != nil { return }
        await withCheckedContinuation { waiting[token] = $0 }
    }
    func release(_ token: String, status: Int) { held.removeValue(forKey: token)?.resume(returning: status) }

    func respond(_ request: URLRequest, body: Data) async throws -> Reply {
        let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        let user = token == "A-refreshed" ? "A" : token
        guard ["A", "B"].contains(user) else {
            return Reply(status: 401, data: Data(#"{"message":"Synthetic expired session"}"#.utf8))
        }
        func json(_ value: Any) throws -> Reply {
            Reply(status: 200, data: try JSONSerialization.data(withJSONObject: value))
        }
        switch request.url!.path {
        case "/api/personal-platform/session":
            identityRequests += 1
            let key = "session-\(token)"
            if holds.contains(key) {
                _ = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                    held[key] = continuation
                    waiting.removeValue(forKey: key)?.resume()
                }
            }
            return try json(["userId": "stable-\(user)", "email": "\(token)@example.invalid"])
        case "/api/auth/sign-out": return try json([:])
        case "/api/auth/delete-user":
            deletions.append(token)
            let key = "delete-\(token)"
            if holds.contains(key) {
                _ = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                    held[key] = continuation
                    waiting.removeValue(forKey: key)?.resume()
                }
            }
            return try json([:])
        case "/v1/sync/push":
            struct Envelope: Decodable { let domain: String; let mutations: [SyncMutation] }
            let envelope = try JSONDecoder().decode(Envelope.self, from: body)
            #expect(envelope.domain == "anchor")
            // Distraction notes and keywords are a hard product boundary —
            // they must never appear in a pushed payload.
            #expect(!String(decoding: body, as: UTF8.self).contains("PRIVATE"))
            for mutation in envelope.mutations {
                if case let .object(fields) = mutation.record {
                    #expect(fields["recordType"] != nil)
                    #expect(fields["note"] == nil && fields["keywords"] == nil)
                }
            }
            pushes.append(Push(token: token, mutations: envelope.mutations))
            let status: Int
            if holds.contains(token) {
                status = await withCheckedContinuation {
                    held[token] = $0
                    waiting.removeValue(forKey: token)?.resume()
                }
            } else { status = failures.contains(token) ? 503 : 200 }
            guard status == 200 else { return Reply(status: status, data: Data("Synthetic unavailable".utf8)) }
            return try json(["results": envelope.mutations.map {
                ["id": $0.id, "idempotencyKey": $0.idempotencyKey, "status": "accepted", "version": user == "A" ? 7 : 19] as [String: Any]
            }])
        case "/v1/sync/pull":
            let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "cursor" }!.value!
            pulls.append(Pull(token: token, cursor: Int(cursor)!))
            let foreign: [String: Any] = [
                "cursor": 1, "changeId": "remote-change", "domain": "anchor", "id": "remote-only-\(user)",
                "operation": "upsert", "version": 1, "occurredAt": "2026-09-01T00:00:00Z",
                "recordedAt": "2026-09-01T00:01:00Z", "originDeviceId": "other-device",
                "record": ["title": "Foreign history must stay remote", "startedAt": "2026-09-01T00:00:00Z",
                           "endedAt": "2026-09-01T00:01:00Z", "durationSeconds": 60, "outcome": "completed", "interruptionCount": 0],
            ]
            return try json(["changes": [foreign] + remoteChanges, "cursor": user == "A" ? 11 : 29, "hasMore": false])
        default: throw URLError(.unsupportedURL)
        }
    }
}

final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static let servers = Mutex<[String: FixtureHub]>([:])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let server = Self.servers.withLock({ $0[request.url!.host!] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                body.append(contentsOf: bytes.prefix(count))
            }
        }
        let requestBody = body
        Task {
            do {
                let reply = try await server.respond(request, body: requestBody)
                let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: reply.data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() {}
}
#endif
