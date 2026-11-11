import Foundation
import Testing
import CaptainsLogKit

/// gws 0.22's `auth login` output, with no terminal: the link on a line of its own, indented.
struct GoogleLoginTests {
    private let link =
        "https://accounts.google.com/o/oauth2/auth?scope=https://www.googleapis.com/auth/calendar&access_type=offline&redirect_uri=http://localhost:54776&response_type=code&client_id=example.apps.googleusercontent.com&prompt=select_account+consent"

    @Test func findsTheLinkOnItsOwnLine() {
        #expect(GoogleLogin.authURL(in: "Open this URL in your browser to authenticate:") == nil)
        #expect(GoogleLogin.authURL(in: "") == nil)
        #expect(GoogleLogin.authURL(in: "  " + link)?.absoluteString == link)
    }

    @Test func failureLeavesOutTheLink() {
        let stderr = "Open this URL in your browser to authenticate:\n\n  \(link)\n\nerror[auth]: access_denied\n"
        #expect(GoogleLogin.failureReason(stderr) == "error[auth]: access_denied")
        #expect(GoogleLogin.failureReason("Open this URL in your browser to authenticate:\n  \(link)\n") == "gws auth login failed")
    }
}
