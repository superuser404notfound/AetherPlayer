import XCTest
import CoreGraphics
import AetherEngine
@testable import AetherPlayer

/// Sodalite#118 in AetherPlayer: Fill zooms past bars painted into the frame.
final class PictureChoiceTests: XCTestCase {
    private let wide = 16.0 / 9.0
    private let full = CGRect(x: 0, y: 0, width: 1, height: 1)
    private let window = CGSize(width: 1920, height: 1080)
    private let scope = PictureArea(rect: CGRect(x: 0, y: 0.128, width: 1, height: 0.744), snappedRatio: 2.39)

    func testMenuOrder() {
        XCTAssertEqual(PictureChoice.all, [.original, .fill(.auto), .fill(.r4x3), .fill(.r185), .fill(.r200), .fill(.r239)])
    }

    func testPickedRatioIsCentredBandOrPillar() throws {
        let pillar = try XCTUnwrap(PictureChoice.fill(.r4x3).area(presentationAspect: wide, detected: nil))
        XCTAssertEqual(pillar.width, 0.75, accuracy: 0.001)
        XCTAssertEqual(pillar.midX, 0.5, accuracy: 0.001)
        let band = try XCTUnwrap(PictureChoice.fill(.r239).area(presentationAspect: wide, detected: nil))
        XCTAssertEqual(band.height, 0.7438, accuracy: 0.001)
        XCTAssertEqual(band.midY, 0.5, accuracy: 0.001)
    }

    func testAutoUsesDetectedAreaOrFullFrame() {
        XCTAssertEqual(PictureChoice.fill(.auto).area(presentationAspect: wide, detected: nil), full)
        XCTAssertEqual(PictureChoice.fill(.auto).area(presentationAspect: wide, detected: scope), scope.rect)
        XCTAssertNil(PictureChoice.original.area(presentationAspect: wide, detected: scope))
    }

    func testOnlyAutoGreysOutAfterAScanThatChangesNothing() {
        XCTAssertFalse(PictureChoice.isEnabled(.fill(.auto), presentationSize: window, surface: window,
                                               detected: .fullFrame, scanState: .finished))
        XCTAssertTrue(PictureChoice.isEnabled(.fill(.auto), presentationSize: window, surface: window,
                                              detected: nil, scanState: .scanning))
        XCTAssertTrue(PictureChoice.isEnabled(.fill(.auto), presentationSize: window, surface: window,
                                              detected: scope, scanState: .finished))
        for choice in PictureChoice.all where choice != .fill(.auto) {
            XCTAssertTrue(PictureChoice.isEnabled(choice, presentationSize: window, surface: window,
                                                  detected: .fullFrame, scanState: .finished))
        }
    }

    func testScanRunsOnlyForAutoOnPlayingVideo() {
        XCTAssertTrue(PlayerViewModel.shouldScanPictureArea(choice: .fill(.auto), isPlaying: true, isLive: false, isAudioOnly: false))
        XCTAssertFalse(PlayerViewModel.shouldScanPictureArea(choice: .fill(.auto), isPlaying: true, isLive: true, isAudioOnly: false))
        XCTAssertFalse(PlayerViewModel.shouldScanPictureArea(choice: .fill(.auto), isPlaying: true, isLive: false, isAudioOnly: true))
        XCTAssertFalse(PlayerViewModel.shouldScanPictureArea(choice: .fill(.r239), isPlaying: true, isLive: false, isAudioOnly: false))
        XCTAssertFalse(PlayerViewModel.shouldScanPictureArea(choice: .original, isPlaying: true, isLive: false, isAudioOnly: false))
    }

    func testRatioLabels() {
        XCTAssertEqual(PictureChoice.ratioLabel(4.0 / 3.0), "4:3")
        XCTAssertEqual(PictureChoice.ratioLabel(1.85), "1.85:1")
        XCTAssertEqual(PictureChoice.ratioLabel(2.39), "2.39:1")
    }

    func testCacheRoundTripPerTitle() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pa-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let url = URL(fileURLWithPath: "/movies/Cars.mkv")
        PictureAreaCache(fileURL: file).store(scope, for: PictureAreaCache.key(url: url, discTitleID: nil))
        let reread = PictureAreaCache(fileURL: file)
        XCTAssertEqual(reread.area(for: PictureAreaCache.key(url: url, discTitleID: nil)), scope)
        XCTAssertNil(reread.area(for: PictureAreaCache.key(url: url, discTitleID: 2)))
    }

    func testCacheEvictsOldest() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pa-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let cache = PictureAreaCache(fileURL: file, capacity: 2)
        for i in 0..<3 { cache.store(scope, for: "k\(i)") }
        XCTAssertNil(cache.area(for: "k0"))
        XCTAssertEqual(cache.area(for: "k2"), scope)
    }

    func testSubtitlePlaneFollowsTheZoom() {
        let band = CGRect(x: 0, y: (1 - (16.0 / 9.0) / 2.39) / 2, width: 1, height: (16.0 / 9.0) / 2.39)
        let plane = SubtitleOverlayView.pictureRect(videoSize: window, in: window, fillArea: band)
        XCTAssertEqual(plane.minY, -186.0, accuracy: 0.5)
        XCTAssertEqual(plane.height, 1452.0, accuracy: 0.5)
        XCTAssertEqual(SubtitleOverlayView.pictureRect(videoSize: window, in: window, fillArea: nil),
                       CGRect(origin: .zero, size: window))
    }

    func testCueInTheCroppedBandStaysOnScreen() {
        let band = CGRect(x: 0, y: (1 - (16.0 / 9.0) / 2.39) / 2, width: 1, height: (16.0 / 9.0) / 2.39)
        // A line authored in the lower letterbox bar of a 16:9 PGS plane.
        let line = CGRect(x: 0.2, y: 0.9, width: 0.6, height: 0.06)
        let frame = SubtitleOverlayView.bitmapCueFrame(position: line, canvas: window, videoSize: window,
                                                       in: window, fillArea: band)
        XCTAssertLessThanOrEqual(frame.maxY, window.height + 0.5)
    }

    /// Pre-merge review: a zoom that crops the sides (a 4:3 pick on a 16:9 file) pushed a wide PGS
    /// line past both window edges, because only the vertical position was held.
    func testWideCueUnderASideCropStaysInsideTheWindow() {
        let pillar = CGRect(x: 0.125, y: 0, width: 0.75, height: 1)
        let line = CGRect(x: 0.075, y: 0.85, width: 0.85, height: 0.08)
        let frame = SubtitleOverlayView.bitmapCueFrame(position: line, canvas: window, videoSize: window,
                                                       in: window, fillArea: pillar)
        XCTAssertGreaterThanOrEqual(frame.minX, -0.5)
        XCTAssertLessThanOrEqual(frame.maxX, window.width + 0.5)
        XCTAssertLessThanOrEqual(frame.maxY, window.height + 0.5)
    }

    /// A line that fits keeps its size and only moves in.
    func testNarrowCueUnderASideCropKeepsItsSize() {
        let pillar = CGRect(x: 0.125, y: 0, width: 0.75, height: 1)
        let line = CGRect(x: 0.05, y: 0.85, width: 0.3, height: 0.08)
        let frame = SubtitleOverlayView.bitmapCueFrame(position: line, canvas: window, videoSize: window,
                                                       in: window, fillArea: pillar)
        XCTAssertEqual(frame.width, 0.3 * 1920 * (4.0 / 3.0), accuracy: 1)
        XCTAssertGreaterThanOrEqual(frame.minX, -0.5)
    }

    /// Opening disc B publishes B's title while the model still names disc A, so that publish is
    /// part of the open, not a title switch.
    func testATitlePublishDuringAnOpenIsNoTitleSwitch() {
        XCTAssertTrue(PlayerViewModel.discTitleChangeResetsPicture(previousID: 0, newID: 3, hasMedia: true, openInFlight: false))
        XCTAssertFalse(PlayerViewModel.discTitleChangeResetsPicture(previousID: 0, newID: 3, hasMedia: true, openInFlight: true))
        XCTAssertFalse(PlayerViewModel.discTitleChangeResetsPicture(previousID: nil, newID: 3, hasMedia: true, openInFlight: false))
        XCTAssertFalse(PlayerViewModel.discTitleChangeResetsPicture(previousID: 3, newID: 3, hasMedia: true, openInFlight: false))
    }
}

/// Review findings on the port: a late result after a reset, the history switch, the hashed key.
@MainActor
final class PictureAreaRunTests: XCTestCase {
    private actor GatedStills: StillSource {
        private var gate: CheckedContinuation<Void, Never>?
        private var opened = false
        func open() { opened = true; gate?.resume(); gate = nil }
        func thumbnailOutcome(at seconds: Double, maxWidth: Int) async -> StillOutcome {
            if !opened { await withCheckedContinuation { gate = $0 } }
            let w = 480, h = 270
            var px = [UInt8](repeating: 0, count: w * h)
            for y in 35..<235 { for x in 0..<w { px[y * w + x] = UInt8(100 + (x * 7 + y * 3) % 60) } }
            let provider = CGDataProvider(data: Data(px) as CFData)!
            return .image(CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!)
        }
    }

    func testLateResultAfterResetIsDropped() async throws {
        let model = try PlayerViewModel()
        let stills = GatedStills()
        let run = model.runPictureAreaScan(source: stills, duration: 7200, displayAspect: 16.0 / 9.0)
        model.resetPicture(seedFromSettings: false)
        await stills.open()
        await run.firstPassDone()
        XCTAssertNil(model.detectedPictureArea)
    }

    /// A replay or a seek from the end reopens the same file; with History off nothing is cached, so
    /// the area has to survive the reset or the bars come back until a new scan.
    func testReopeningTheSameFileKeepsTheArea() throws {
        let model = try PlayerViewModel()
        let scope = PictureArea(rect: CGRect(x: 0, y: 0.128, width: 1, height: 0.744), snappedRatio: 2.39)
        model.detectedPictureArea = scope
        model.resetPicture(seedFromSettings: false, keepsArea: true)
        XCTAssertEqual(model.detectedPictureArea, scope)
        model.resetPicture(seedFromSettings: false)
        XCTAssertNil(model.detectedPictureArea)
    }

    func testCacheKeyCarriesNoURL() {
        let key = PictureAreaCache.key(url: URL(string: "https://host.example/movie.mkv?api_key=secret")!, discTitleID: nil)
        XCTAssertFalse(key.contains("secret"))
        XCTAssertFalse(key.contains("host.example"))
        XCTAssertEqual(key.count, 64)
    }

    func testClearWipesTheFile() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pa-\(UUID().uuidString).json")
        let cache = PictureAreaCache(fileURL: file)
        cache.store(.fullFrame, for: "k")
        cache.clear()
        XCTAssertNil(cache.area(for: "k"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
