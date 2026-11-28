import AetherEngine
import Foundation
#if os(macOS)
import AppKit
#endif

/// The switch and the wipe for everything the app remembers about what was played: the recents list
/// with its resume points, their thumbnail cache, the remembered live URLs and, on macOS, the
/// system's File > Open Recent list, the segments a stopped session kept for a reopen (AE#1095) and the
/// picture areas Fill (Auto) found (Sodalite#118). One place, so the switch and the wipe cannot drift apart.
enum PlaybackHistory {
    static let enabledKey = "history.enabled"

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    @MainActor
    static func clear() {
        RecentsStore.shared.clearAll()
        RecentsThumbnailProvider.shared.clearCache()
        LiveStreamMemory.clear()
        AetherEngine.discardRetainedSessionCache()
        PictureAreaCache.shared.clear()
        #if os(macOS)
        NSDocumentController.shared.clearRecentDocuments(nil)
        #endif
    }
}
