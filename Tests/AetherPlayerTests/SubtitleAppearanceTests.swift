import XCTest
import CoreGraphics
@testable import AetherPlayer

/// Subtitle appearance (#9): where text sits, how far bitmaps follow it, and that the ASS canvas is
/// the picture rather than the window.
final class SubtitleAppearanceTests: XCTestCase {

    func testDefaultPositionKeepsHistoricalGap() {
        XCTAssertEqual(subtitleBottomInset(position: .standard, surfaceHeight: 1080), 48)
        XCTAssertEqual(subtitleBitmapShift(position: .standard, surfaceHeight: 1080), 0)
    }

    func testBottomEdgeKeepsMinimumGapAndLeavesBitmaps() {
        XCTAssertEqual(subtitleBottomInset(position: .bottom, surfaceHeight: 1080), subtitleMinimumBottomInset)
        XCTAssertEqual(subtitleBitmapShift(position: .bottom, surfaceHeight: 1080), 0)
    }

    func testRaisedStepsMoveTextAndBitmapsTogether() {
        XCTAssertEqual(subtitleBottomInset(position: .low, surfaceHeight: 1000), 100, accuracy: 0.001)
        XCTAssertEqual(subtitleBottomInset(position: .mid, surfaceHeight: 1000), 300, accuracy: 0.001)
        XCTAssertEqual(subtitleBitmapShift(position: .midLow, surfaceHeight: 1000), -200, accuracy: 0.001)
    }

    func testDefaultsDecodeToTodaysLook() {
        let style = SubtitleTextStyle()
        XCTAssertEqual(style.size, .normal)
        XCTAssertEqual(style.background, .box)
        XCTAssertEqual(style.position, .standard)
        XCTAssertEqual(style.color, .white)
    }

    func testOutlineGrowsWithTextButNeverVanishes() {
        XCTAssertEqual(subtitleOutlineWidth(pointSize: 6), 1)
        XCTAssertEqual(subtitleOutlineWidth(pointSize: 28), 2, accuracy: 0.001)
        XCTAssertGreaterThan(subtitleOutlineWidth(pointSize: 72), subtitleOutlineWidth(pointSize: 28))
    }

    func testRaisedBitmapIsClampedOntoSurface() {
        // A top-of-plane sign lifted by 30% would leave the surface; it is pulled back to the top.
        let sign = CGRect(x: 0.3, y: 0.05, width: 0.4, height: 0.06)
        let bounds = CGSize(width: 1920, height: 1080)
        let frame = SubtitleOverlayView.bitmapCueFrame(
            position: sign, canvas: bounds, videoSize: bounds, in: bounds,
            verticalShift: subtitleBitmapShift(position: .mid, surfaceHeight: bounds.height))
        XCTAssertEqual(frame.minY, 0, accuracy: 0.001)
    }

    func testASSCanvasIsThePictureOnAnUltrawideWindow() {
        // 16:9 film in a 21:9 window: the canvas is pillarboxed, not stretched to the window.
        let rect = SubtitleOverlayView.aspectFitRect(videoSize: CGSize(width: 1920, height: 1080),
                                                     in: CGSize(width: 3440, height: 1440))
        XCTAssertEqual(rect.width, 2560, accuracy: 0.001)
        XCTAssertEqual(rect.height, 1440, accuracy: 0.001)
        XCTAssertEqual(rect.minX, 440, accuracy: 0.001)
    }
}
