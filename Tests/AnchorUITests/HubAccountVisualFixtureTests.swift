#if os(macOS)
@testable import AnchorCore
@testable import AnchorUI
import AppKit
import Foundation
import PersonalSyncKit
import SwiftData
import SwiftUI
import Testing

/// Opt-in evidence fixture. Production code has no demo identity or auth bypass.
@Suite("Connected Hub account visual fixture", .serialized)
@MainActor
struct HubAccountVisualFixtureTests {
    @Test("Render the real connected account panel with synthetic identity and planner sharing off/on")
    func renderConnectedPanel() async throws {
        guard let directory = ProcessInfo.processInfo.environment["ANCHOR_ASSISTANT_EVIDENCE_DIR"], !directory.isEmpty else { return }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let support = FileManager.default.temporaryDirectory.appending(path: "anchor-visual-fixture-\(UUID())")
        let suiteName = "anchor-visual-fixture-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: support)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VisualIdentityProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let origin = URL(string: "https://anchor-visual-fixture.invalid")!
        let identity = PersonalIdentityClient(baseURL: origin, session: transport, tokenStore: VisualTokenStore())
        let container = try AnchorStore.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let platform = AnchorPlatformSync(
            context: context, identity: identity, supportDirectory: support,
            deviceId: UUID().uuidString.lowercased(), receiptStore: HubSyncReceiptStore(defaults: defaults),
            transport: transport, platformURL: origin, identityOrigin: origin, observeLocalSaves: false
        )
        await platform.account?.restore()
        #expect(platform.account?.isSignedIn == true)
        #expect(await platform.approveHubHistory())
        #expect(!platform.needsHistoryApproval)

        var pages: [[String: Any]] = []
        for enabled in [false, true] {
            if enabled { #expect(await platform.setPlannerSharingEnabled(true)) }
            #expect(platform.isPlannerSharingEnabled == enabled)
            for width in [390, 820, 1280] {
                let content = HubAccountPanel(platform: platform, presentation: .settings)
                    .padding(24)
                    .frame(width: CGFloat(width), alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(AnchorTheme.dark.canvas)
                    .anchorTheme()
                    .environment(\.colorScheme, .dark)
                    .environment(\.horizontalSizeClass, width < 600 ? .compact : .regular)
                    .modelContainer(container)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                let image = try #require(renderer.cgImage)
                let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                let name = "hub-connected-sharing-\(enabled ? "on" : "off")-\(width).png"
                try png.write(to: output.appending(path: name))
                pages.append(["file": name, "widthPoints": width, "heightPoints": image.height / 2, "sharingEnabled": enabled])
            }
        }
        let manifest: [String: Any] = [
            "renderPlatform": "macOS rendering of the shared SwiftUI HubAccountPanel; not an iOS simulator screenshot",
            "view": "HubAccountPanel presentation settings",
            "identity": "Synthetic URLProtocol identity and in-memory bearer token; no Keychain or external network",
            "sourceRevision": "cfebb3e",
            "pages": pages,
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appending(path: "manifest.json"))
    }
}

private actor VisualTokenStore: PersonalBearerTokenStore {
    private var token: String? = "synthetic-visual-token"
    func load() -> String? { token }
    func save(_ value: String) { token = value }
    func delete() { token = nil }
}

/// Intercepts every request, including unexpected origins: none can reach the network.
private final class VisualIdentityProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "anchor-visual-fixture.invalid",
              request.url?.path == "/api/personal-platform/session",
              request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-visual-token" else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let body = Data(#"{"userId":"synthetic-visual-owner","email":"alex@example.invalid"}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
