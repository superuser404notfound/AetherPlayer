import SwiftUI

struct PlayerChrome: View {
    let model: PlayerViewModel
    @State private var controlsVisible = true
    @State private var lastActivity = Date()
    @State private var scrubbing = false
    @State private var showTracks = false
    @State private var showStats = false

    private let hideInterval: TimeInterval = 3.5

    var body: some View {
        ZStack {
            PlayerGestureCatcher(
                onToggleControls: { toggleControls() },
                onSkip: { model.flashHUD($0 >= 0 ? .skipForward : .skipBackward); model.seek(by: $0); bumpActivity() },
                onTogglePlayPause: { model.togglePlayPause(); bumpActivity() },
                onSetBrightness: { model.setBrightness($0) },
                onSetVolume: { model.setVolume($0) }
            )
            // On-frame subtitles: above the video/catcher, below the controls and HUD. Non-hittable so
            // it never intercepts taps; the transport bar sits above it when controls are shown.
            SubtitleOverlay(model: model)
                .allowsHitTesting(false)
            // Stats for Nerds: a top-leading translucent panel over the video, toggled from the Tracks
            // sheet. Mounted below the controls so the transport bar and HUD stay on top. Stays visible
            // while toggled on (independent of controlsVisible). Scrolls internally if content overflows.
            if showStats {
                StatsInspectorView(model: model)
                    .frame(maxWidth: 340, maxHeight: .infinity, alignment: .top)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 60)
                    .padding([.leading, .bottom], 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if controlsVisible {
                VStack {
                    PlayerTopBar(model: model, onTracks: { showTracks = true; bumpActivity() })
                    Spacer()
                    PlayerTransportBar(model: model, scrubbing: $scrubbing)
                }
                .transition(.opacity)
            }
            // Edge affordances hinting the vertical brightness/volume swipes. Shown with the controls,
            // hidden while scrubbing so they do not clutter the scrub preview.
            if controlsVisible && !scrubbing {
                PlayerSwipeHints()
                    .transition(.opacity)
            }
            // Touch/volume HUD: mounted above the chrome so it shows while controls are hidden (volume is
            // usually changed with the chrome down). Non-hittable so its 0-opacity frame never eats gestures.
            PlayerHUD(kind: model.hudKind ?? model.lastHudKind, level: model.hudLevel)
                .opacity(model.hudKind == nil ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: model.hudKind)
                .allowsHitTesting(false)
            // Notices (the lip-sync value, the audio-drop warning) sit under where the top bar draws and
            // are shown whether the chrome is up or not: the delay is adjusted from the Tracks sheet, and
            // the drop warning is not something the viewer asked for at all.
            if let notice = model.notice {
                VStack {
                    HStack(spacing: 8) {
                        if notice.kind == .warning {
                            Image(systemName: "speaker.slash.fill")
                        }
                        Text(notice.text)
                    }
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 70)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity)
                .task(id: notice.id) {
                    try? await Task.sleep(for: .seconds(notice.seconds))
                    model.dismissNotice(id: notice.id)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.notice)
        .sheet(isPresented: $showTracks) { TracksSheet(model: model, showStats: $showStats) }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard controlsVisible else { return }          // hidden: leave hidden
            if scrubbing || showTracks {                   // keep up while scrubbing / sheet open
                lastActivity = Date(); return
            }
            if shouldHideControls(now: Date().timeIntervalSinceReferenceDate,
                                  lastActivity: lastActivity.timeIntervalSinceReferenceDate,
                                  interval: hideInterval) {
                withAnimation { controlsVisible = false }
            }
        }
    }

    /// Single tap: toggle. Hiding must NOT go through bumpActivity (which forces visible).
    private func toggleControls() {
        if controlsVisible {
            withAnimation { controlsVisible = false }
        } else {
            lastActivity = Date()
            withAnimation { controlsVisible = true }
        }
    }
    /// A user action (skip / play / open tracks): reset the timer and ensure controls are up.
    private func bumpActivity() {
        lastActivity = Date()
        if !controlsVisible { withAnimation { controlsVisible = true } }
    }
}
