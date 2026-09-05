import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AetherEngine

struct ContentView: View {
    @State private var model: PlayerViewModel
    @State private var isDropTargeted = false
    let onOpenURL: () -> Void

    init(model: PlayerViewModel, onOpenURL: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onOpenURL = onOpenURL
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.hasMedia {
                if model.isAudioOnly {
                    NowPlayingView(model: model)
                        .ignoresSafeArea()
                } else {
                    PlayerContainerView(model: model)
                        .ignoresSafeArea()
                }
            } else {
                EmptyStateView(
                    isDropTargeted: isDropTargeted,
                    onOpen: openPanel,
                    onOpenURL: onOpenURL,
                    recents: model.recents.items,
                    thumbnails: model.recentsThumbnails,
                    onOpenRecent: { item in Task { await model.openRecent(item) } },
                    onRemoveRecent: { model.recents.remove($0) },
                    onClearRecents: { model.recents.clearAll() }
                )
            }

            if model.state == .loading && !model.hasMedia {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Opening stream\u{2026}")
                        Button("Cancel") { model.cancelLoading() }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let err = model.loadError {
                VStack {
                    Spacer()
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, 24)
                }
                .transition(.opacity)
            }

            // Top-centre rather than at the bottom with the other two toasts: the audio-drop notice and
            // the resume toast both arrive right after a load, and the delay notice would otherwise sit
            // under the transport bar, which is up while someone is nudging by ear.
            if let notice = model.notice {
                VStack {
                    HStack(spacing: 8) {
                        if notice.kind == .warning {
                            Image(systemName: "speaker.slash.fill")
                        }
                        Text(notice.text)
                    }
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 24)
                    Spacer()
                }
                .transition(.opacity)
                .task(id: notice.id) {
                    try? await Task.sleep(for: .seconds(notice.seconds))
                    model.dismissNotice(id: notice.id)
                }
            }

            if let msg = model.resumeMessage {
                VStack {
                    Spacer()
                    ResumeToastView(message: msg, onStartOver: { model.startOver() })
                        .padding(.bottom, 90)
                }
                .transition(.opacity)
                .task(id: msg) {
                    try? await Task.sleep(for: .seconds(6))
                    model.dismissResumeMessage()
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.loadError)
        .animation(.easeInOut(duration: 0.25), value: model.resumeMessage)
        .animation(.easeInOut(duration: 0.2), value: model.notice)
        .animation(.easeInOut(duration: 0.2), value: model.state == .loading)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    if isDir.boolValue {
                        let bm = BookmarkAccess.bookmark(for: url)
                        await model.openFolder(url, bookmarkData: bm)
                    } else if Self.subtitleExtensions.contains(url.pathExtension.lowercased()), model.hasMedia {
                        // A subtitle file dropped onto a playing video attaches as
                        // a sidecar track; anything else loads as a new video.
                        model.loadSidecarSubtitle(url: url)
                    } else {
                        await model.open(url: url)
                    }
                }
            }
            return true
        }
        .onChange(of: model.loadedURL) { _, _ in updateWindowTitle() }
        .onChange(of: model.metadata) { _, _ in updateWindowTitle() }
        .onChange(of: model.isAudioOnly) { _, _ in updateWindowTitle() }
        .onChange(of: model.loadError) { _, err in
            // Auto-dismiss the error toast after a few seconds, unless a newer
            // error replaced it in the meantime.
            guard err != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                if model.loadError == err { model.clearLoadError() }
            }
        }
    }

    /// Sidecar subtitle file extensions recognized on drop.
    private static let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub"]

    private func updateWindowTitle() {
        NSApp.keyWindow?.title = windowTitle(
            metadata: model.metadata, url: model.loadedURL, isAudio: model.isAudioOnly)
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .audio, .discImage]
        if panel.runModal() == .OK, let url = panel.url {
            Task { await model.open(url: url) }
        }
    }
}
