import XCTest
import AetherEngine
@testable import AetherPlayer

final class TrackMenuModelTests: XCTestCase {
    private func audio(_ id: Int, _ name: String, lang: String? = nil, ch: Int = 2, atmos: Bool = false) -> TrackInfo {
        TrackInfo(id: id, name: name, codec: "eac3", language: lang, channels: ch, isDefault: false, isAtmos: atmos)
    }

    func testAudioRowLabelsIncludeLanguageAndChannels() {
        let rows = audioMenuRows([audio(0, "English", lang: "en", ch: 6)], activeIndex: 0)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].label, "English · EN · 5.1")
        XCTAssertTrue(rows[0].isSelected)
        XCTAssertEqual(rows[0].engineIndex, 0)
    }

    func testAtmosOverridesChannelLabel() {
        let rows = audioMenuRows([audio(0, "Surround", lang: "en", ch: 6, atmos: true)], activeIndex: nil)
        XCTAssertEqual(rows[0].label, "Surround · EN · Atmos")
        XCTAssertFalse(rows[0].isSelected)
    }

    func testAudioDescriptionTrackIsMarked() {
        let ad = TrackInfo(id: 0, name: "English", codec: "aac", language: "en", channels: 2, isDefault: false,
                           isVisualImpaired: true)
        XCTAssertEqual(audioMenuRows([ad], activeIndex: nil)[0].label, "English · EN · Stereo · Audio Description")
    }

    func testStereoAndUnknownChannelLabels() {
        XCTAssertEqual(audioMenuRows([audio(0, "A", ch: 2)], activeIndex: nil)[0].label, "A · Stereo")
        XCTAssertEqual(audioMenuRows([audio(0, "B", ch: 8)], activeIndex: nil)[0].label, "B · 7.1")
    }

    func testSubtitleRowsPrependOffAndMarkSelection() {
        let subs = [TrackInfo(id: 3, name: "English", codec: "subrip", language: "en", channels: 0, isDefault: false)]
        let off = subtitleMenuRows(subs, selectedEngineIndex: nil, isActive: false)
        XCTAssertEqual(off.first?.kind, .off)
        XCTAssertTrue(off.first!.isSelected)
        let on = subtitleMenuRows(subs, selectedEngineIndex: 3, isActive: true)
        XCTAssertFalse(on.first!.isSelected)
        XCTAssertEqual(on.last?.label, "English · EN")
        XCTAssertTrue(on.last!.isSelected)
    }

    func testTitleRowsLabelAndSelection() {
        let titles = [
            TitleInfo(id: 0, name: "Title 1", durationSeconds: 7325, chapterCount: 12),
            TitleInfo(id: 1, name: "Title 2", durationSeconds: 0, chapterCount: 0),
        ]
        let rows = titleMenuRows(titles, selectedID: 0)
        XCTAssertEqual(rows[0].label, "Title 1 · 2:02:05 · 12 ch")
        XCTAssertTrue(rows[0].isSelected)
        XCTAssertEqual(rows[1].label, "Title 2")          // no duration / chapters -> name only
        XCTAssertFalse(rows[1].isSelected)
    }

    func testChapterRowsLabel() {
        let chapters = [
            ChapterInfo(id: 0, name: "Chapter 1", startSeconds: 0, durationSeconds: 600),
            ChapterInfo(id: 1, name: "Chapter 2", startSeconds: 754, durationSeconds: 600),
        ]
        let rows = chapterMenuRows(chapters)
        XCTAssertEqual(rows.map(\.id), [0, 1])
        XCTAssertEqual(rows[0].label, "Chapter 1 · 0:00:00")
        XCTAssertEqual(rows[1].label, "Chapter 2 · 0:12:34")
    }
}
