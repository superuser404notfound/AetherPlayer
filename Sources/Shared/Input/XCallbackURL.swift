import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Where to send the user once an x-callback-url session is over.
struct XCallbackTargets: Equatable, Sendable {
    var success: URL?
    var error: URL?
    var cancel: URL?

    enum ErrorCode: Int, Sendable {
        case invalidRequest = 1
        case unsupportedAction = 2
        case playbackFailed = 3
    }

    /// Closing the player before the end. Without an x-cancel the caller still gets the user back
    /// through x-success, which is what Infuse and Outplayer do.
    var cancelURL: URL? { cancel ?? success }

    /// x-error with the spec's `errorCode` and `errorMessage` appended to whatever query it carries.
    func errorURL(code: ErrorCode, message: String) -> URL? {
        guard let error, var components = URLComponents(url: error, resolvingAgainstBaseURL: false) else { return nil }
        // Encoded by hand: URLComponents leaves `&`, `=` and `+` in a value as they are, so a message
        // containing one would split into a second parameter at the caller.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?")
        let message = message.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let appended = "errorCode=\(code.rawValue)&errorMessage=\(message)"
        components.percentEncodedQuery = [components.percentEncodedQuery, appended]
            .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "&")
        return components.url
    }
}

/// `aetherplayer://x-callback-url/play?url=<media>&x-success=...&x-error=...&x-cancel=...`
struct XCallbackRequest: Equatable, Sendable {
    let mediaURL: URL
    let live: Bool
    let targets: XCallbackTargets
}

enum XCallbackURL {
    static let scheme = "aetherplayer"

    enum Parsed: Equatable {
        case play(XCallbackRequest)
        case rejected(XCallbackTargets, code: XCallbackTargets.ErrorCode, message: String)
    }

    /// nil when `url` is not ours (a file handed over by the system, for instance).
    static func parse(_ url: URL) -> Parsed? {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        let targets = XCallbackTargets(
            success: callbackURL(value("x-success")),
            error: callbackURL(value("x-error")),
            cancel: callbackURL(value("x-cancel")))

        // `aetherplayer://x-callback-url/play` is the spec form; `aetherplayer://play` is accepted too.
        let host = components.host?.lowercased() ?? ""
        let path = components.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let action = host == "x-callback-url" ? path : host
        guard action == "play" else {
            return .rejected(targets, code: .unsupportedAction, message: "Unsupported action: \(action)")
        }
        guard let media = value("url").flatMap(MediaURLValidation.normalized) else {
            return .rejected(targets, code: .invalidRequest, message: "Missing or invalid url parameter")
        }
        return .play(XCallbackRequest(mediaURL: media, live: isTrue(value("live")), targets: targets))
    }

    /// A callback may go to any app, but never back to us (a loop) or to a file, which the system
    /// would open with whatever app claims it.
    static func callbackURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme != Self.scheme, scheme != "file" else { return nil }
        return url
    }

    private static func isTrue(_ text: String?) -> Bool {
        guard let text = text?.lowercased() else { return false }
        return ["1", "true", "yes"].contains(text)
    }

    @MainActor
    static func send(_ url: URL?) {
        guard let url else { return }
        DiagnosticsLog.shared.note("x-callback-url: returning to \(url.scheme ?? "?")")
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}
