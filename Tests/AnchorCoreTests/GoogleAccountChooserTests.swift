import Foundation
import Testing
@testable import AnchorCore

struct GoogleAccountChooserTests {
    @Test func asksGoogleToChooseIdentityAndGrantOfflineConsent() throws {
        let request = try GoogleCalendarConfig.makeAuthorizationRequest(clientID: "test.apps.googleusercontent.com")
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let prompt = try #require(items.first { $0.name == "prompt" }?.value)
        #expect(Set(prompt.split(separator: " ")) == ["select_account", "consent"])
    }

    @Test func distinguishesWorkspacePolicyAfterCheckingState() throws {
        for (code, expected) in [("admin_policy_enforced", GoogleCalendarError.workspacePolicy),
                                 ("org_internal", .organizationOnly)] {
            let callback = try #require(URL(string: "test:/oauth2callback?state=s1&error=\(code)"))
            #expect(throws: expected) { try GoogleCalendarConfig.authorizationCode(fromCallback: callback, expectedState: "s1") }
            #expect(throws: GoogleCalendarError.invalidResponse) {
                try GoogleCalendarConfig.authorizationCode(fromCallback: callback, expectedState: "other")
            }
        }
    }
}
