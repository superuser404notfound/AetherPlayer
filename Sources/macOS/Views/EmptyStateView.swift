import SwiftUI

struct EmptyStateView: View {
    let isDropTargeted: Bool
    let onOpen: () -> Void
    let onOpenURL: () -> Void
    let recents: [RecentItem]
    let thumbnails: RecentsThumbnailProvider
    let onOpenRecent: (RecentItem) -> Void
    let onRemoveRecent: (RecentItem) -> Void
    let onClearRecents: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    if recents.isEmpty {
                        Spacer(minLength: 0)
                    }
                    VStack(spacing: 16) {
                        Image(systemName: "play.square.stack")
                            .font(.system(size: 64))
                            .foregroundStyle(isDropTargeted
                                ? AnyShapeStyle(Color.aetherPurple)
                                : AnyShapeStyle(.white.opacity(0.45)))
                            .shadow(color: .aetherPurple.opacity(isDropTargeted ? 0.7 : 0), radius: 16)
                        Text(isDropTargeted ? String(localized: "Release to load") : String(localized: "Drop a video or audio file here"))
                            .font(.title2)
                            .foregroundStyle(isDropTargeted
                                ? AnyShapeStyle(Color.aetherPurple)
                                : AnyShapeStyle(.white.opacity(0.65)))
                        HStack {
                            Button("Open File\u{2026}", action: onOpen)
                            Button("Open URL\u{2026}", action: onOpenURL)
                        }
                        .controlSize(.large)
                        Text("MKV, MP4, WebM, AVI \u{00B7} MP3, FLAC, WAV, M4A, OGG")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    if !recents.isEmpty {
                        RecentsListView(items: recents, thumbnails: thumbnails, onOpen: onOpenRecent,
                                        onRemove: onRemoveRecent, onClearAll: onClearRecents)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .padding(.top, recents.isEmpty ? 40 : 24)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}
