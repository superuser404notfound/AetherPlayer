import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
import UniformTypeIdentifiers
import AetherEngine

/// Decodes and caches keyframe thumbnails for recents entries. Each entry is
/// an arbitrary file (not the playing item), so we resolve its security-scoped
/// bookmark, build a one-off `FrameExtractor`, decode, then shut it down. A
/// disk cache (keyed by path + size/mtime) makes thumbnails instant across
/// launches; an in-memory map short-circuits repeats within a session. One instance serves every
/// window, so a new window does not decode the whole list again.
@MainActor
final class RecentsThumbnailProvider {
    static let shared = RecentsThumbnailProvider()

    private var memory: [String: CGImage] = [:]
    /// Entries that decoded to nothing this session (above all audio without cover art, which has no
    /// disk cache entry), so each window that lists them does not probe the file again.
    private var misses: Set<String> = []
    /// One decode per entry, however many windows ask for it at once.
    private var inFlight: [String: Task<CGImage?, Never>] = [:]
    private let cacheDir: URL
    /// Cover-art probes read the file with blocking I/O. On the cooperative pool a slow volume
    /// fills every thread with them, and every other task in the app waits, a player's load included.
    private static let probeQueue = DispatchQueue(label: "AetherPlayer.recents.coverart", qos: .utility)

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDir = base.appendingPathComponent("RecentsThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Thumbnail for a recents entry, or nil if the file is offline or decode
    /// fails. Safe to call repeatedly (memory + disk cached).
    func thumbnail(for item: RecentItem) async -> CGImage? {
        if let cached = memory[item.id] { return cached }
        if misses.contains(item.id) { return nil }
        if let running = inFlight[item.id] { return await running.value }

        let task = Task { await decode(item) }
        inFlight[item.id] = task
        let image = await task.value
        inFlight[item.id] = nil
        return image
    }

    /// Drops the memory and disk caches, for Clear History. A decode still in flight may write its
    /// file afterwards; the next clear takes it.
    func clearCache() {
        memory.removeAll()
        misses.removeAll()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private func decode(_ item: RecentItem) async -> CGImage? {
        guard let scoped = ScopedResource(bookmark: item.bookmarkData) else { return nil }
        defer { scoped.stop() }

        let cacheURL = cacheFile(id: item.id, stamp: Self.validityStamp(for: scoped.url))
        if let disk = Self.loadImage(cacheURL) {
            memory[item.id] = disk
            return disk
        }

        let ext = scoped.url.pathExtension.lowercased()
        let image: CGImage?
        if audioExtensions.contains(ext) {
            image = await Self.coverArtImage(for: scoped.url)
        } else {
            let extractor = FrameExtractor(url: scoped.url)
            image = await extractor.thumbnail(
                at: recentsThumbnailTime(duration: item.duration), maxWidth: 320)
            await extractor.shutdown()
        }

        if let image {
            memory[item.id] = image
            Self.writeJPEG(image, to: cacheURL)
        } else {
            misses.insert(item.id)
        }
        return image
    }

    /// Decode embedded cover art for an audio file via a one-shot engine
    /// probe, run off the main actor so the recents list stays responsive.
    /// Returns nil when the file has no attached picture (the recents row
    /// then shows its generic placeholder, unchanged).
    private static func coverArtImage(for url: URL) async -> CGImage? {
        let data = await withCheckedContinuation { (done: CheckedContinuation<Data?, Never>) in
            probeQueue.async {
                done.resume(returning: (try? AetherEngine.probe(url: url))?.metadata.artworkData)
            }
        }
        guard let data,
              let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    // MARK: - Cache file naming

    private func cacheFile(id: String, stamp: String) -> URL {
        let digest = SHA256.hash(data: Data("\(id)|\(stamp)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent("\(hex).jpg")
    }

    private static func validityStamp(for url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size)-\(Int(mtime))"
    }

    // MARK: - Image IO

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(
            dest, image,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}
