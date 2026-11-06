import XCTest
import CoreGraphics
@testable import AetherPlayer

/// Bitmap cue positions are normalized to the subtitle composition canvas, which is a plane of
/// its own: a 720p encode routinely carries the disc's 1920x1080 PGS plane. Scaling that plane by
/// coded video pixels assumes canvas and video share a pixel grid, true for a scope crop off a
/// disc (both 1920 wide) and false for a downscaled encode, where it blew the canvas up by 1.5x,
/// so the line rendered 1.5x too wide and ran off the bottom edge of the surface.
final class BitmapSubtitleCanvasTests: XCTestCase {

    /// A typical authored dialogue line: centered, in the lower eighth of the plane.
    private let bottomLine = CGRect(x: 0.2, y: 0.86, width: 0.6, height: 0.06)
    private let bounds = CGSize(width: 1920, height: 1080)
    private let hdCanvas = CGSize(width: 1920, height: 1080)

    func testDownscaledEncodeKeepsAuthoredGeometry() {
        let frame = SubtitleOverlayView.bitmapCueFrame(position: bottomLine, canvas: hdCanvas,
                                                       videoSize: CGSize(width: 1280, height: 720),
                                                       in: bounds)
        XCTAssertLessThanOrEqual(frame.maxY, bounds.height)
        XCTAssertEqual(frame.minX, 384, accuracy: 0.001)
        XCTAssertEqual(frame.width, 1152, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 928.8, accuracy: 0.001)
        XCTAssertEqual(frame.height, 64.8, accuracy: 0.001)
    }

    func testDownscaledScopeCropStaysOnSurface() {
        // 2.39:1 cropped to 1280x536, PGS still authored on the 1920x1080 plane.
        let frame = SubtitleOverlayView.bitmapCueFrame(position: bottomLine, canvas: hdCanvas,
                                                       videoSize: CGSize(width: 1280, height: 536),
                                                       in: bounds)
        XCTAssertLessThanOrEqual(frame.maxY, bounds.height)
        XCTAssertEqual(frame.minY, 928.8, accuracy: 0.001)
        XCTAssertEqual(frame.width, 1152, accuracy: 0.001)
    }

    func testScopeCropKeepsLowerBarPlacement() {
        // The case the canvas mapping was built for: video cropped to scope, canvas still 16:9,
        // and a line authored below the picture stays in the bar instead of riding up into it.
        let barLine = CGRect(x: 0.2, y: 0.90, width: 0.6, height: 0.05)
        let frame = SubtitleOverlayView.bitmapCueFrame(position: barLine, canvas: hdCanvas,
                                                       videoSize: CGSize(width: 1920, height: 804),
                                                       in: bounds)
        XCTAssertEqual(frame.minX, 384, accuracy: 0.001)
        XCTAssertEqual(frame.width, 1152, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 972, accuracy: 0.001)
        // Below the video picture (bottom edge at 138 + 804), still on the surface.
        XCTAssertGreaterThan(frame.minY, 942)
        XCTAssertLessThanOrEqual(frame.maxY, bounds.height)
    }

    func testPortraitPinsCueToVideoBand() {
        let portrait = CGSize(width: 390, height: 844)
        let frame = SubtitleOverlayView.bitmapCueFrame(position: bottomLine, canvas: hdCanvas,
                                                       videoSize: hdCanvas, in: portrait)
        // Video band: 390x219.375 centered vertically.
        XCTAssertEqual(frame.minX, 78, accuracy: 0.001)
        XCTAssertEqual(frame.width, 234, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 500.975, accuracy: 0.001)
        XCTAssertEqual(frame.height, 13.1625, accuracy: 0.001)
        XCTAssertLessThanOrEqual(frame.maxY, 312.3125 + 219.375)
    }

    func testMatchingCanvasMapsOntoVideoRect() {
        let frame = SubtitleOverlayView.bitmapCueFrame(position: bottomLine, canvas: hdCanvas,
                                                       videoSize: hdCanvas, in: bounds)
        XCTAssertEqual(frame.minX, 384, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 928.8, accuracy: 0.001)
        XCTAssertEqual(frame.width, 1152, accuracy: 0.001)
    }

    func testAnamorphicCanvasWidensWithThePicture() {
        // DVB / DVD on 720x576 at 16:9 (pixel aspect 64:45): the engine reports the coded frame as
        // the canvas, the picture presents at 1024x576 and fills a 16:9 surface.
        let pixelAspect: CGFloat = 64.0 / 45.0
        let frame = SubtitleOverlayView.bitmapCueFrame(position: bottomLine,
                                                       canvas: CGSize(width: 720, height: 576),
                                                       videoSize: CGSize(width: 720 * pixelAspect, height: 576),
                                                       pixelAspect: pixelAspect, in: bounds)
        XCTAssertEqual(frame.minX, 384, accuracy: 0.001)
        XCTAssertEqual(frame.width, 1152, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 928.8, accuracy: 0.001)
        XCTAssertEqual(frame.height, 64.8, accuracy: 0.001)
    }

    func testAnamorphicCroppedRipKeepsRows() {
        // 720x432 cut out of a 720x480 DVD at pixel aspect 32:27; the engine keeps the 720x480
        // canvas since the widths match. Canvas row 0.86 * 480 = 412.8, minus 24 rows cropped off the top.
        let pixelAspect: CGFloat = 32.0 / 27.0
        let surface = CGSize(width: 720 * pixelAspect, height: 432)
        let frame = SubtitleOverlayView.bitmapCueFrame(position: bottomLine,
                                                       canvas: CGSize(width: 720, height: 480),
                                                       videoSize: CGSize(width: 720 * pixelAspect, height: 432),
                                                       pixelAspect: pixelAspect, in: surface)
        XCTAssertEqual(frame.minY, 388.8, accuracy: 0.001)
        XCTAssertEqual(frame.height, 28.8, accuracy: 0.001)
        XCTAssertEqual(frame.width, 512, accuracy: 0.001)
    }

    func testUnknownVideoDimsFallBackToBounds() {
        let frame = SubtitleOverlayView.bitmapCueFrame(position: bottomLine, canvas: hdCanvas,
                                                       videoSize: .zero, in: bounds)
        XCTAssertEqual(frame.minX, 384, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 928.8, accuracy: 0.001)
        XCTAssertEqual(frame.width, 1152, accuracy: 0.001)
        XCTAssertEqual(frame.height, 64.8, accuracy: 0.001)
    }
}
