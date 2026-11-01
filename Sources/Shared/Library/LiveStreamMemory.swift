import Foundation

/// Remembers which remote URLs turned out to be live streams, so reopening one
/// loads directly on the engine's live path (single tune-in, no size probing)
/// instead of paying the VOD probe plus live reload again. Plain UserDefaults
/// string list, newest first, capped; remote URLs are not part of RecentsStore
/// (that list is bookmark-backed local files).
enum LiveStreamMemory {
    private static let key = "liveStreams.v1"
    private static let limit = 50

    static func remember(_ url: URL, defaults: UserDefaults = .standard) {
        guard PlaybackHistory.isEnabled(defaults) else { return }
        let id = url.absoluteString
        var list = defaults.stringArray(forKey: key) ?? []
        list.removeAll { $0 == id }
        list.insert(id, at: 0)
        if list.count > limit { list.removeLast(list.count - limit) }
        defaults.set(list, forKey: key)
    }

    static func isKnownLive(_ url: URL, defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: key) ?? []).contains(url.absoluteString)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
