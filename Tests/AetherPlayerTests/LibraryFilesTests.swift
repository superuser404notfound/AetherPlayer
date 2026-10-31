import XCTest
@testable import AetherPlayer

final class LibraryFilesTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("LibraryFilesTests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func touch(_ name: String, in folder: URL? = nil) throws -> URL {
        let url = (folder ?? root).appendingPathComponent(name)
        try Data([0]).write(to: url)
        return url
    }

    func testEntriesListFoldersFirstInFinderOrderWithoutHiddenFiles() throws {
        _ = try touch("ep10.mkv")
        _ = try touch("ep2.mkv")
        _ = try touch(".DS_Store")
        try LibraryFiles.createFolder(named: "Shows", in: root)
        let entries = LibraryFiles.entries(in: root)
        XCTAssertEqual(entries.map(\.name), ["Shows", "ep2.mkv", "ep10.mkv"])
        XCTAssertTrue(entries[0].isFolder)
        XCTAssertNil(entries[0].size)
        XCTAssertEqual(entries[1].size, 1)
    }

    func testPlayableIncludesDiscImagesButNotSubtitles() throws {
        let iso = LibraryFiles.Entry(url: root.appendingPathComponent("disc.ISO"), isFolder: false, size: 1)
        let srt = LibraryFiles.Entry(url: root.appendingPathComponent("film.srt"), isFolder: false, size: 1)
        XCTAssertTrue(iso.isPlayable)
        XCTAssertFalse(srt.isPlayable)
    }

    func testAvailableURLNumbersBeforeTheExtension() throws {
        _ = try touch("film.mkv")
        _ = try touch("film 2.mkv")
        XCTAssertEqual(LibraryFiles.availableURL(for: "film.mkv", in: root).lastPathComponent, "film 3.mkv")
        XCTAssertEqual(LibraryFiles.availableURL(for: "new.mkv", in: root).lastPathComponent, "new.mkv")
        try LibraryFiles.createFolder(named: "Box", in: root)
        XCTAssertEqual(LibraryFiles.availableURL(for: "Box", in: root).lastPathComponent, "Box 2")
    }

    func testValidatedNameRejectsPathsHiddenAndEmpty() {
        XCTAssertEqual(LibraryFiles.validatedName("  Film  "), "Film")
        XCTAssertNil(LibraryFiles.validatedName("   "))
        XCTAssertNil(LibraryFiles.validatedName(".hidden"))
        XCTAssertNil(LibraryFiles.validatedName("a/b"))
        XCTAssertNil(LibraryFiles.validatedName("a:b"))
    }

    func testRenameRefusesATakenNameButAllowsACaseChange() throws {
        let a = try touch("a.mkv")
        _ = try touch("b.mkv")
        XCTAssertThrowsError(try LibraryFiles.rename(a, to: "b.mkv")) {
            XCTAssertEqual($0 as? LibraryFiles.Failure, .nameTaken("b.mkv"))
        }
        let upper = try LibraryFiles.rename(a, to: "A.mkv")
        XCTAssertEqual(upper.lastPathComponent, "A.mkv")
        XCTAssertTrue(LibraryFiles.entries(in: root).map(\.name).contains("A.mkv"))
    }

    func testMoveRefusesToOverwrite() throws {
        let box = try LibraryFiles.createFolder(named: "Box", in: root)
        let a = try touch("a.mkv")
        _ = try touch("a.mkv", in: box)
        XCTAssertThrowsError(try LibraryFiles.move(a, into: box))
        let b = try touch("b.mkv")
        let moved = try LibraryFiles.move(b, into: box)
        XCTAssertTrue(fm.fileExists(atPath: moved.path))
        XCTAssertFalse(fm.fileExists(atPath: b.path))
    }

    func testImportCopyKeepsTheSourceAndPicksAFreeName() throws {
        let source = try touch("film.mkv")
        let box = try LibraryFiles.createFolder(named: "Box", in: root)
        _ = try touch("film.mkv", in: box)
        let copy = try LibraryFiles.importCopy(of: source, into: box)
        XCTAssertEqual(copy.lastPathComponent, "film 2.mkv")
        XCTAssertTrue(fm.fileExists(atPath: source.path))
    }

    func testFolderTreeSkipsTheExcludedSubtree() throws {
        let a = try LibraryFiles.createFolder(named: "A", in: root)
        try LibraryFiles.createFolder(named: "Inner", in: a)
        try LibraryFiles.createFolder(named: "B", in: root)
        let all = LibraryFiles.folderTree(root: root)
        XCTAssertEqual(all.map { $0.url.lastPathComponent }, [root.lastPathComponent, "A", "Inner", "B"])
        XCTAssertEqual(all.map(\.depth), [0, 1, 2, 1])
        let withoutA = LibraryFiles.folderTree(root: root, excluding: a)
        XCTAssertEqual(withoutA.map { $0.url.lastPathComponent }, [root.lastPathComponent, "B"])
    }

    func testContainmentTreatsPrivateVarAsVar() {
        let folder = URL(fileURLWithPath: "/private/var/mobile/Docs")
        XCTAssertTrue(LibraryFiles.isSameOrInside(URL(fileURLWithPath: "/var/mobile/Docs/a.mkv"), folder))
        XCTAssertTrue(LibraryFiles.isSameOrInside(URL(fileURLWithPath: "/var/mobile/Docs"), folder))
        XCTAssertFalse(LibraryFiles.isSameOrInside(URL(fileURLWithPath: "/var/mobile/Docs2/a.mkv"), folder))
    }
}
