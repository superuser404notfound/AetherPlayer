import SwiftUI
import AppKit
import AetherEngine

struct PlayerContainerView: View {
    let model: PlayerViewModel

    @State private var controlsVisible = true
    @State private var lastActivity = Date()
    @State private var showTracks = false
    /// True while the user is dragging the scrubber. Keeps the controls from
    /// auto-hiding mid-drag, which would tear down the slider and drop the
    /// deferred seek.
    @State private var scrubbing = false
    private let hideInterval: TimeInterval = 3
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Bottom layer: mouse-move tracker (needs hit testing to receive mouseMoved).
            MouseActivityView { bumpActivity() }

            AetherPlayerSurface(engine: model.engine)

            // Click layer above the surface: single click = play/pause,
            // double click = fullscreen. The single click waits for the double
            // to fail so a double-click does not also toggle playback.
            ClickView(
                onSingle: { model.primaryAction(); bumpActivity() },
                onDouble: { toggleFullScreen(); bumpActivity() }
            )

            // Subtitle state (incl. the ~10 Hz subtitleTime clock) is observed
            // inside SubtitleOverlay, not here, so this container body does not
            // re-evaluate every tick during undisturbed playback. (issue #2)
            SubtitleOverlay(model: model)
                .allowsHitTesting(false)

            if controlsVisible {
                VStack {
                    Spacer()
                    TransportBar(
                        model: model,
                        onTracksTapped: { showTracks.toggle() },
                        onPrevious: { ensureFolderThenAdvance(next: false) },
                        onNext: { ensureFolderThenAdvance(next: true) },
                        scrubbing: $scrubbing
                    )
                }
                .transition(.opacity)
                .popover(isPresented: $showTracks, arrowEdge: .bottom) {
                    TracksPopover(model: model)
                }
            }

            KeyCatcherView(onKey: handleKey)
                .allowsHitTesting(false)
        }
        .onAppear { NSApp.keyWindow?.acceptsMouseMovedEvents = true }
        .onDisappear { NSCursor.setHiddenUntilMouseMoves(false) }
        .onChange(of: controlsVisible) { _, visible in
            updateCursorVisibility(controlsVisible: visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            updateCursorVisibility(for: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            updateCursorVisibility(for: notification)
        }
        .onReceive(tick) { _ in
            if shouldHideControls(now: Date().timeIntervalSinceReferenceDate,
                                  lastActivity: lastActivity.timeIntervalSinceReferenceDate,
                                  interval: hideInterval),
               model.isPlaying, !showTracks, !scrubbing {
                withAnimation { controlsVisible = false }
            }
        }
    }

    private func bumpActivity() {
        lastActivity = Date()
        if !controlsVisible { withAnimation { controlsVisible = true } }
    }

    private func updateCursorVisibility(for notification: Notification) {
        guard let window = notification.object as? NSWindow, window.isKeyWindow else { return }
        updateCursorVisibility(controlsVisible: controlsVisible, window: window)
    }

    private func updateCursorVisibility(controlsVisible: Bool, window: NSWindow? = NSApp.keyWindow) {
        let isFullScreen = window?.styleMask.contains(.fullScreen) == true
        NSCursor.setHiddenUntilMouseMoves(
            shouldHideCursor(controlsVisible: controlsVisible, isFullScreen: isFullScreen)
        )
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 49: model.primaryAction(); bumpActivity(); return true     // Space
        case 53:  // Esc: exit fullscreen if in fullscreen, else stop
            if NSApp.keyWindow?.styleMask.contains(.fullScreen) == true {
                toggleFullScreen()
            } else {
                model.stop()
            }
            return true
        case 124 where event.modifierFlags.contains(.command):          // Cmd+Right = next
            ensureFolderThenAdvance(next: true); bumpActivity(); return true
        case 123 where event.modifierFlags.contains(.command):          // Cmd+Left = previous
            ensureFolderThenAdvance(next: false); bumpActivity(); return true
        case 123: model.seek(by: -10); bumpActivity(); return true      // Left
        case 124: model.seek(by: 10); bumpActivity(); return true       // Right
        case 126: model.adjustVolume(by: 0.05); bumpActivity(); return true  // Up
        case 125: model.adjustVolume(by: -0.05); bumpActivity(); return true // Down
        case 46: model.toggleMute(); bumpActivity(); return true        // M
        case 3:  toggleFullScreen(); return true                        // F
        // J / K, the pair every other player uses for this. No bumpActivity: the on-screen notice states
        // the new value on its own, and raising the transport bar over the picture is the opposite of
        // what someone matching lip movement by ear needs.
        case 38: model.adjustAudioDelay(by: -AudioDelay.step); return true   // J
        case 40: model.adjustAudioDelay(by: AudioDelay.step); return true    // K
        default: return false
        }
    }

    private func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    private func ensureFolderThenAdvance(next: Bool) {
        if model.playlist != nil {
            Task { if next { await model.playNext() } else { await model.playPrevious() } }
            return
        }
        guard let current = model.loadedURL else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = current.deletingLastPathComponent()
        panel.message = "Grant access to this folder to play the next file."
        if panel.runModal() == .OK, let folder = panel.url {
            let bm = BookmarkAccess.bookmark(for: folder)
            model.adoptFolderPlaylist(folderURL: folder, around: current, bookmarkData: bm)
            Task { if next { await model.playNext() } else { await model.playPrevious() } }
        }
    }
}

/// Transparent overlay that distinguishes single from double click using a
/// short, fixed window (rather than the generous system double-click interval
/// the gesture recognizers use). A second click within `interval` cancels the
/// pending single action and fires the double instead.
private struct ClickView: NSViewRepresentable {
    let onSingle: () -> Void
    let onDouble: () -> Void

    func makeNSView(context: Context) -> _ClickNSView {
        let v = _ClickNSView()
        v.onSingle = onSingle
        v.onDouble = onDouble
        return v
    }

    func updateNSView(_ nsView: _ClickNSView, context: Context) {
        nsView.onSingle = onSingle
        nsView.onDouble = onDouble
    }

    final class _ClickNSView: NSView {
        var onSingle: (() -> Void)?
        var onDouble: (() -> Void)?
        private var pendingSingle: DispatchWorkItem?
        /// Single-click wait and double-click window. Shorter than the system
        /// default for a snappier single click.
        private let interval: TimeInterval = 0.35

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { /* claim the click; act on mouseUp */ }

        override func mouseUp(with event: NSEvent) {
            if let pending = pendingSingle {
                pending.cancel()
                pendingSingle = nil
                onDouble?()
            } else {
                let work = DispatchWorkItem { [weak self] in
                    self?.pendingSingle = nil
                    self?.onSingle?()
                }
                pendingSingle = work
                DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
            }
        }
    }
}

/// Tracks mouse movement over the player and reports activity.
private struct MouseActivityView: NSViewRepresentable {
    let onMove: () -> Void
    func makeNSView(context: Context) -> _Tracking {
        let v = _Tracking(); v.onMove = onMove; return v
    }
    func updateNSView(_ nsView: _Tracking, context: Context) { nsView.onMove = onMove }

    final class _Tracking: NSView {
        var onMove: (() -> Void)?
        private var area: NSTrackingArea?
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let a = NSTrackingArea(rect: bounds,
                                   options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
                                   owner: self, userInfo: nil)
            addTrackingArea(a); area = a
        }
        override func mouseMoved(with event: NSEvent) { onMove?() }
    }
}
