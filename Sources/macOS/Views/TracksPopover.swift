import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AetherEngine

struct TracksPopover: View {
    let model: PlayerViewModel

    private var audioRows: [AudioMenuRow] {
        audioMenuRows(model.audioTracks, activeIndex: model.activeAudioTrackIndex)
    }
    private var subtitleRows: [SubtitleMenuRow] {
        subtitleMenuRows(model.subtitleTracks,
                         selectedEngineIndex: model.selectedSubtitleIndex,
                         isActive: model.isSubtitleActive)
    }
    private var titleRows: [TitleMenuRow] {
        titleMenuRows(model.discTitles, selectedID: model.selectedDiscTitleID)
    }
    private var chapterRows: [ChapterMenuRow] {
        chapterMenuRows(model.discChapters)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !titleRows.isEmpty {
                    Text("Titles").font(.headline)
                    ForEach(titleRows) { row in
                        rowButton(row.label, selected: row.isSelected) {
                            model.selectTitle(id: row.id)
                        }
                    }
                    Divider()
                }
                if !chapterRows.isEmpty {
                    Text("Chapters").font(.headline)
                    ForEach(chapterRows) { row in
                        Button(action: { model.selectChapter(id: row.id) }) {
                            HStack {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(row.label)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Divider()
                }
                if !audioRows.isEmpty {
                    Text("Audio").font(.headline)
                    ForEach(audioRows) { row in
                        rowButton(row.label, selected: row.isSelected) {
                            model.selectAudio(engineIndex: row.engineIndex)
                        }
                    }
                    Divider()
                }
                Text("Subtitles").font(.headline)
                ForEach(subtitleRows) { row in
                    rowButton(row.label, selected: row.isSelected) {
                        switch row.kind {
                        case .off: model.disableSubtitle()
                        case .track(let idx): model.selectSubtitle(engineIndex: idx)
                        }
                    }
                }
                Button("Load Subtitle File\u{2026}", action: loadSidecar)
                    .padding(.top, 4)
                if !model.isAudioOnly {
                    Divider()
                    Text("Picture").font(.headline)
                    ForEach(PictureChoice.all, id: \.self) { choice in
                        rowButton(model.pictureChoiceTitle(choice), selected: choice == model.activePictureChoice) {
                            model.selectPictureChoice(choice)
                        }
                        .disabled(!model.isPictureChoiceEnabled(choice))
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 280)
        .frame(maxHeight: tracksPopoverMaxHeight(
            screenHeight: NSScreen.main?.visibleFrame.height ?? 800))
    }

    @ViewBuilder
    private func rowButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? AnyShapeStyle(Color.aetherPurple) : AnyShapeStyle(.secondary))
                Text(label)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func loadSidecar() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText,
                                     UTType(filenameExtension: "ass") ?? .plainText,
                                     UTType(filenameExtension: "vtt") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            model.loadSidecarSubtitle(url: url)
        }
    }
}
