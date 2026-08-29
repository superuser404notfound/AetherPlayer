import AetherEngine
import AVFoundation
import Darwin
import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// Session log of the engine's diagnostic lines, written to a file the user can hand over.
///
/// `EngineLog.handler` is the engine's only diagnostic sink, and it used to be installed inside
/// `#if DEBUG` pointing at `print`, so a shipped build produced no diagnostics at all. Every
/// playback report then cost a round trip asking for lines the reporter had no way to produce:
/// AetherPlayer#2 ran four of those over three weeks without ever obtaining the one log line that
/// would have named the failing attribute. The handler is now always installed and every line also
/// lands here.
///
/// The handler fires from arbitrary engine threads, so appends are serialized onto a dedicated
/// queue and the file handle is touched only there.
///
/// Every line carries a fixed-width UTC stamp (`LogTimestamp`), the same format Sodalite's in-app
/// diagnostic log uses, so a file handed over from either app can be diffed against the other and
/// against a server log without knowing what zone the reporter sat in. It replaced a local-time
/// `HH:mm:ss.SSS`, which needed the session header to be read first and rolled silently over midnight.
final class DiagnosticsLog: @unchecked Sendable {

    static let shared = DiagnosticsLog()

    /// Rotate at 8 MB, keeping one previous file. The rotated file holds the session header and the
    /// load phase, which is where a failure-to-start is described; the live file holds the tail,
    /// which is where a mid-playback stall is. Keeping both means neither question needs the other
    /// file to have survived.
    private let maxBytes = 8 * 1024 * 1024

    private let queue = DispatchQueue(label: "de.superuser404.aetherplayer.diagnostics", qos: .utility)
    private var handle: FileHandle?
    private var written = 0
    private var started = false

    /// `~/Library/Logs/AetherPlayer` (the sandbox container's Library for the MAS build).
    let directory: URL
    /// The live session log. Stable path so a reporter can be pointed at it once.
    let currentURL: URL
    private let previousURL: URL

    private init() {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = library.appendingPathComponent("Logs/AetherPlayer", isDirectory: true)
        currentURL = directory.appendingPathComponent("AetherPlayer.log")
        previousURL = directory.appendingPathComponent("AetherPlayer-previous.log")
    }

    // MARK: - Lifecycle

    /// Installs the engine's diagnostic sink and opens a fresh session log. Idempotent: both app
    /// targets construct a `PlayerViewModel` exactly once, but a second call must not rotate the
    /// file out from under the first session's lines.
    func start() {
        queue.sync {
            guard !started else { return }
            started = true
            rotateLocked()
        }
        EngineLog.handler = { [weak self] line in
            #if DEBUG
            // Keep stdout for `devicectl process launch --console` and Xcode runs.
            print(line)
            #endif
            self?.append(line)
        }
    }

    /// The stamp is taken here rather than inside the queue block, so it dates the moment the line was
    /// emitted rather than the moment this serial queue got round to writing it. Under the load that
    /// makes a log worth reading (a stall, a burst of segment fetches) those two are not the same
    /// instant, and an append-time stamp would have quietly reported the backlog instead of the event.
    func append(_ line: String) {
        let stamp = LogTimestamp.stamp()
        queue.async { [self] in
            guard started else { return }
            if written >= maxBytes { rotateLocked() }
            writeLocked(stamp + "  " + line + "\n")
        }
    }

    /// A line from the app rather than the engine, tagged so the two are distinguishable.
    func note(_ line: String) {
        append("[AetherPlayer] " + line)
    }

    /// A source rendered for a log that gets handed over: a local file contributes its name and not
    /// the library layout around it, a remote source its scheme, host and name and not the query
    /// string, which is where a session token would sit.
    static func describe(_ url: URL) -> String {
        guard !url.isFileURL else { return url.lastPathComponent }
        let scheme = url.scheme ?? "?"
        let host = url.host ?? "?"
        let name = url.lastPathComponent
        return name.isEmpty ? "\(scheme)://\(host)" : "\(scheme)://\(host)/\u{2026}/\(name)"
    }

    // MARK: - Handing it over

    /// Writes previous + current into one file under a self-describing name and returns it, for the
    /// macOS save panel and the iOS share sheet. Returns nil when nothing has been logged yet.
    func exportSnapshot() -> URL? {
        queue.sync {
            try? handle?.synchronize()
        }
        let fm = FileManager.default
        let parts = [previousURL, currentURL].filter { fm.fileExists(atPath: $0.path) }
        guard !parts.isEmpty else { return nil }

        let name = DateFormatter()
        name.dateFormat = "yyyy-MM-dd-HHmmss"
        name.locale = Locale(identifier: "en_US_POSIX")
        let destination = fm.temporaryDirectory
            .appendingPathComponent("AetherPlayer-diagnostics-\(name.string(from: Date())).log")

        fm.createFile(atPath: destination.path, contents: nil)
        guard let out = try? FileHandle(forWritingTo: destination) else { return nil }
        defer { try? out.close() }
        for part in parts {
            guard let data = try? Data(contentsOf: part) else { continue }
            try? out.write(contentsOf: data)
        }
        return destination
    }

    #if canImport(AppKit)
    func revealInFinder() {
        // Select the live log rather than opening the folder, so the file to attach is unambiguous
        // even once a rotated sibling sits next to it.
        NSWorkspace.shared.activateFileViewerSelecting([currentURL])
    }
    #endif

    // MARK: - File plumbing (queue only)

    private func rotateLocked() {
        try? handle?.close()
        handle = nil
        written = 0

        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: currentURL.path) {
            try? fm.removeItem(at: previousURL)
            try? fm.moveItem(at: currentURL, to: previousURL)
        }
        fm.createFile(atPath: currentURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: currentURL)
        writeLocked(Self.sessionHeader())
    }

    private func writeLocked(_ text: String) {
        guard let handle, let data = text.data(using: .utf8) else { return }
        try? handle.write(contentsOf: data)
        written += data.count
    }

    /// The environment facts a playback report is otherwise asked for one at a time.
    /// `eligibleForHDRPlayback` earns its place: it is the input that decides whether a HDR source
    /// is served as a master playlist or media-direct, so a routing question is answerable from the
    /// log instead of from a guess about the reporter's monitor.
    private static func sessionHeader() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let memory = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif

        // Both readings of one instant. The lines below are UTC, so the header has to be too or the
        // file cannot be lined up against a server log; the local rendering stays because the offset it
        // carries is the only thing in here that says which zone the reporter was in.
        let localOpened = DateFormatter()
        localOpened.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        localOpened.locale = Locale(identifier: "en_US_POSIX")
        let now = Date()

        return """
        === AetherPlayer diagnostics ===
        opened      \(LogTimestamp.stamp(now)) (local \(localOpened.string(from: now)))
        app         \(version) (\(build)) \(configuration)
        os          \(os)
        hardware    \(sysctlString("hw.model")) / \(sysctlString("hw.machine")) / \(sysctlString("hw.ncpu")) cpus / \(memory) GB
        hdr         AVPlayer.eligibleForHDRPlayback=\(AVPlayer.eligibleForHDRPlayback)
        note        contains media file names, no paths beyond them
        ================================

        """
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "?" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "?" }
        // hw.ncpu is an Int32, not a string; render whichever the name actually holds.
        if size == MemoryLayout<Int32>.size {
            return String(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
