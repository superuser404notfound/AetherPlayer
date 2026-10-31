import Foundation

/// The iOS Library tab: the app's Documents folder, which `UIFileSharingEnabled` exposes in the Files
/// app and in Finder. Plain FileManager calls, kept in Shared so the macOS test target covers them.
enum LibraryFiles {
    struct Entry: Identifiable, Hashable {
        let url: URL
        let isFolder: Bool
        let size: Int64?
        var id: URL { url }
        var name: String { url.lastPathComponent }
        var isPlayable: Bool { !isFolder && libraryPlayableExtensions.contains(url.pathExtension.lowercased()) }
    }

    struct FolderNode: Identifiable, Hashable {
        let url: URL
        let depth: Int
        var id: URL { url }
    }

    enum Failure: LocalizedError, Equatable {
        case invalidName
        case nameTaken(String)

        var errorDescription: String? {
            switch self {
            case .invalidName: String(localized: "That name cannot be used.")
            case .nameTaken(let name): String(localized: "An item named “\(name)” already exists.")
            }
        }
    }

    /// Disc images open from a file as well; `playableExtensions` leaves them out because a folder
    /// playlist should not step into one.
    static let libraryPlayableExtensions = playableExtensions.union(["iso"])

    static var root: URL { URL.documentsDirectory }

    /// Folders first, then files, each in Finder order. Hidden entries (`.Trash`, a `.DS_Store` that
    /// Finder copied in) stay out.
    static func entries(in folder: URL, fileManager: FileManager = .default) -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let urls = (try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let entries = urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isFolder = values?.isDirectory ?? false
            return Entry(url: url, isFolder: isFolder, size: isFolder ? nil : values?.fileSize.map(Int64.init))
        }
        return entries.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Every folder under `root`, `root` first, depth-first in Finder order. `excluding` drops that
    /// folder and everything inside it, which is where a folder cannot be moved to.
    static func folderTree(root: URL = root, excluding: URL? = nil, fileManager: FileManager = .default) -> [FolderNode] {
        var nodes: [FolderNode] = []
        func walk(_ folder: URL, depth: Int) {
            if let excluding, isSameOrInside(folder, excluding) { return }
            nodes.append(FolderNode(url: folder, depth: depth))
            for entry in entries(in: folder, fileManager: fileManager) where entry.isFolder {
                walk(entry.url, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return nodes
    }

    /// `name` in `folder`, or `name 2`, `name 3`, ... before the extension when it is taken.
    static func availableURL(for name: String, in folder: URL, fileManager: FileManager = .default) -> URL {
        let candidate = folder.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var n = 2
        while true {
            let next = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let url = folder.appendingPathComponent(next)
            if !fileManager.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }

    /// A name the user typed, trimmed, or nil when it cannot name a file: empty, a path, or hidden.
    static func validatedName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":") else { return nil }
        return name
    }

    @discardableResult
    static func createFolder(named raw: String, in folder: URL, fileManager: FileManager = .default) throws -> URL {
        guard let name = validatedName(raw) else { throw Failure.invalidName }
        let url = folder.appendingPathComponent(name, isDirectory: true)
        guard !fileManager.fileExists(atPath: url.path) else { throw Failure.nameTaken(name) }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    @discardableResult
    static func rename(_ url: URL, to raw: String, fileManager: FileManager = .default) throws -> URL {
        guard let name = validatedName(raw) else { throw Failure.invalidName }
        guard name != url.lastPathComponent else { return url }
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        // A change of case only is the same file on a case-insensitive volume, so the existence
        // check would refuse it.
        let caseOnly = name.lowercased() == url.lastPathComponent.lowercased()
        guard caseOnly || !fileManager.fileExists(atPath: target.path) else { throw Failure.nameTaken(name) }
        try fileManager.moveItem(at: url, to: target)
        return target
    }

    @discardableResult
    static func move(_ url: URL, into folder: URL, fileManager: FileManager = .default) throws -> URL {
        let target = folder.appendingPathComponent(url.lastPathComponent)
        guard !fileManager.fileExists(atPath: target.path) else { throw Failure.nameTaken(url.lastPathComponent) }
        try fileManager.moveItem(at: url, to: target)
        return target
    }

    /// Copies a picked file in, under a free name. Copy, not move: the picker hands out files that
    /// belong to another provider, and those stay where the user keeps them.
    @discardableResult
    static func importCopy(of source: URL, into folder: URL, fileManager: FileManager = .default) throws -> URL {
        let target = availableURL(for: source.lastPathComponent, in: folder, fileManager: fileManager)
        try fileManager.copyItem(at: source, to: target)
        return target
    }

    /// The same path whether it was spelled through `/var` or `/private/var`: the container is
    /// handed out in both forms, and a deleted file can no longer be resolved to compare.
    static func canonicalPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        return path.hasPrefix("/private/var/") ? String(path.dropFirst("/private".count)) : path
    }

    static func isSameOrInside(_ url: URL, _ folder: URL) -> Bool {
        let path = canonicalPath(url), base = canonicalPath(folder)
        return path == base || path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    /// Whether `url` lives in the app's own container, where it needs no security scope.
    static func isInAppContainer(_ url: URL) -> Bool {
        isSameOrInside(url, URL.homeDirectory)
    }
}
