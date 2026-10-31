import Foundation

/// Security-scoped bookmark helpers. Under the App Sandbox a URL granted by
/// an open panel / drop / Finder open is only reachable for this launch;
/// a security-scoped bookmark lets us reopen it later.
enum BookmarkAccess {
    /// Create security-scoped bookmark data for a file or folder. `.withSecurityScope` is a
    /// macOS App Sandbox option and is unavailable on iOS; iOS grants security scope on
    /// resolution for URLs handed out by the document picker without that creation flag.
    static func bookmark(for url: URL) -> Data? {
        #if os(macOS)
        try? url.bookmarkData(options: .withSecurityScope,
                              includingResourceValuesForKeys: nil,
                              relativeTo: nil)
        #else
        try? url.bookmarkData(options: [],
                              includingResourceValuesForKeys: nil,
                              relativeTo: nil)
        #endif
    }
}

/// Resolves a bookmark and holds its security scope until `stop()` (or deinit).
/// Use one per active file/folder; stop it when you load something else.
final class ScopedResource {
    let url: URL
    let isStale: Bool
    private var active: Bool

    init?(bookmark data: Data) {
        var stale = false
        #if os(macOS)
        guard let resolved = try? URL(resolvingBookmarkData: data,
                                      options: .withSecurityScope,
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &stale) else { return nil }
        #else
        guard let resolved = try? URL(resolvingBookmarkData: data,
                                      options: [],
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &stale) else { return nil }
        #endif
        // A file in the app's own container (the iOS Library) carries no security scope, so starting
        // access on it fails although the file is reachable.
        let started = resolved.startAccessingSecurityScopedResource()
        guard started || LibraryFiles.isInAppContainer(resolved) else { return nil }
        self.url = resolved
        self.isStale = stale
        self.active = started
    }

    func stop() {
        guard active else { return }
        url.stopAccessingSecurityScopedResource()
        active = false
    }

    deinit { stop() }
}
