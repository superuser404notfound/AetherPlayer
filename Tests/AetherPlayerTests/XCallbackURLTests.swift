import Testing
import Foundation
@testable import AetherPlayer

struct XCallbackURLTests {
    private func parse(_ text: String) -> XCallbackURL.Parsed? {
        XCallbackURL.parse(URL(string: text)!)
    }

    @Test func parsesPlayWithCallbacks() throws {
        let parsed = parse("aetherplayer://x-callback-url/play?url=https%3A%2F%2Fx.com%2Fa.mkv%3Fapi_key%3D1%26b%3D2"
            + "&x-success=shortcuts%3A%2F%2Fdone&x-error=myapp%3A%2F%2Ffail&x-cancel=myapp%3A%2F%2Fback")
        guard case .play(let request) = parsed else { Issue.record("not a play request"); return }
        #expect(request.mediaURL.absoluteString == "https://x.com/a.mkv?api_key=1&b=2")
        #expect(request.live == false)
        #expect(request.targets.success?.absoluteString == "shortcuts://done")
        #expect(request.targets.error?.absoluteString == "myapp://fail")
        #expect(request.targets.cancel?.absoluteString == "myapp://back")
    }

    @Test func acceptsShortFormAndLiveFlag() {
        guard case .play(let request) = parse("aetherplayer://play?url=http://tuner.local/ch1&live=1") else {
            Issue.record("not a play request"); return
        }
        #expect(request.live)
        #expect(request.targets == XCallbackTargets())
    }

    @Test func ignoresOtherSchemes() {
        #expect(parse("file:///Users/x/a.mkv") == nil)
        #expect(parse("https://x.com/a.mkv") == nil)
    }

    @Test func rejectsMissingOrUnsupportedMediaURL() {
        guard case let .rejected(targets, code, _) = parse("aetherplayer://x-callback-url/play?url=ftp://x.com/a&x-error=app://e") else {
            Issue.record("expected rejection"); return
        }
        #expect(code == .invalidRequest)
        #expect(targets.error?.absoluteString == "app://e")
        guard case let .rejected(_, missing, _) = parse("aetherplayer://x-callback-url/play") else {
            Issue.record("expected rejection"); return
        }
        #expect(missing == .invalidRequest)
    }

    @Test func rejectsUnknownAction() {
        guard case let .rejected(_, code, _) = parse("aetherplayer://x-callback-url/record?url=https://x.com/a") else {
            Issue.record("expected rejection"); return
        }
        #expect(code == .unsupportedAction)
    }

    @Test func dropsCallbacksToFilesAndToItself() {
        #expect(XCallbackURL.callbackURL("file:///Applications/Calculator.app") == nil)
        #expect(XCallbackURL.callbackURL("aetherplayer://x-callback-url/play?url=https://x.com") == nil)
        #expect(XCallbackURL.callbackURL("not a url") == nil)
        #expect(XCallbackURL.callbackURL("https://example.com/back")?.host == "example.com")
    }

    @Test func cancelFallsBackToSuccess() {
        let success = URL(string: "app://ok")!
        #expect(XCallbackTargets(success: success).cancelURL == success)
        #expect(XCallbackTargets(success: success, cancel: URL(string: "app://no")!).cancelURL?.absoluteString == "app://no")
    }

    @Test func errorURLAppendsCodeAndMessage() throws {
        let targets = XCallbackTargets(error: URL(string: "app://fail?id=7")!)
        let url = try #require(targets.errorURL(code: .playbackFailed, message: "Not found & gone"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "id" }?.value == "7")
        #expect(items.first { $0.name == "errorCode" }?.value == "3")
        #expect(items.first { $0.name == "errorMessage" }?.value == "Not found & gone")
        #expect(XCallbackTargets().errorURL(code: .invalidRequest, message: "x") == nil)
    }
}
