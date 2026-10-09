import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct AetherPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var model: PlayerViewModel? = {
        try? PlayerViewModel()
    }()
    @State private var alwaysOnTop = false
    @State private var showOpenURLSheet = false
    @Environment(\.openWindow) private var openWindow
#if DIRECT_DISTRIBUTION
    @StateObject private var updater = Updater()
#endif

    var body: some Scene {
        Window("AetherPlayer", id: "main") {
            Group {
                if let model {
                    ContentView(model: model) {
                        showOpenURLSheet = true
                    }
                    .sheet(isPresented: $showOpenURLSheet) {
                        OpenURLSheet(model: model)
                    }
                } else {
                    Text("AetherEngine failed to initialize.")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                }
            }
            .onAppear {
                NSApp.windows.first?.setFrameAutosaveName("AetherPlayerMainWindow")
                if let model {
                    // Activation/fronting is handled in AppDelegate; just load.
                    AppDelegate.onOpenFiles = { urls in
                        guard let url = urls.first else { return }
                        Task { @MainActor in await model.open(url: url) }
                    }
                }
            }
            .onChange(of: alwaysOnTop) { _, on in
                NSApp.keyWindow?.level = on ? .floating : .normal
            }
            .frame(minWidth: 640, minHeight: 360)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About AetherPlayer") { AboutPanel.show() }
            }
#if DIRECT_DISTRIBUTION
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") { updater.checkForUpdates() }
            }
#endif
            CommandGroup(after: .appInfo) {
                Button("Open Source Licenses\u{2026}") { openWindow(id: "licenses") }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open\u{2026}") { openFile() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Open URL\u{2026}") { showOpenURLSheet = true }
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(model == nil)
                Button("Open Folder\u{2026}") { openFolderPanel() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Frame As\u{2026}") {
                    if let model { SnapshotSaver.captureAndSave(model: model) }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model?.hasMedia != true)
            }
            // The value first, as in the Audio menu. The video surface also takes [ ] and \ bare (the
            // keys IINA and mpv use); the Command versions here are the ones a text field cannot eat.
            CommandMenu("Playback") {
                if let model {
                    Text("Speed: \(rateLabel(model.rate))")
                    Button("Faster") { model.stepRateFaster() }
                        .keyboardShortcut("]", modifiers: .command)
                        .disabled(!model.hasMedia || PlaybackSpeed.faster(than: model.rate) == nil)
                    Button("Slower") { model.stepRateSlower() }
                        .keyboardShortcut("[", modifiers: .command)
                        .disabled(!model.hasMedia || PlaybackSpeed.slower(than: model.rate) == nil)
                    Button("Normal Speed") { model.resetRate() }
                        .keyboardShortcut("\\", modifiers: .command)
                        .disabled(!model.hasMedia || model.rate == PlaybackSpeed.normal)
                    Divider()
                    ForEach(PlaybackSpeed.rates, id: \.self) { r in
                        Button(action: { model.setRate(r) }) {
                            Text((model.rate == r ? "\u{2713} " : "") + rateLabel(r))
                        }
                        .disabled(!model.hasMedia)
                    }
                }
            }
            CommandMenu("Audio") {
                if let model {
                    ForEach(audioMenuRows(model.audioTracks, activeIndex: model.activeAudioTrackIndex)) { row in
                        Button(action: { model.selectAudio(engineIndex: row.engineIndex) }) {
                            Text((row.isSelected ? "\u{2713} " : "") + row.label)
                        }
                    }
                    Divider()
                    // Flat, with the value first: it reads as the heading of the three rows under it, and
                    // this is the one number a viewer nudging by ear wants without opening anything.
                    // The keys J and K do the same two steps on the video surface (KeyCatcherView), which
                    // is where the rest of the single-key transport lives. They are deliberately not menu
                    // key equivalents here: a bare letter as a menu shortcut fires from a text field too,
                    // and this app has one in the Open URL sheet.
                    Text("Audio delay: \(AudioDelay.label(model.audioDelaySeconds))")
                    Button("Delay Audio (+\(Int(AudioDelay.step * 1000)) ms)") {
                        model.adjustAudioDelay(by: AudioDelay.step)
                    }
                    .disabled(!model.canAdjustAudioDelay(by: AudioDelay.step))
                    Button("Advance Audio (-\(Int(AudioDelay.step * 1000)) ms)") {
                        model.adjustAudioDelay(by: -AudioDelay.step)
                    }
                    .disabled(!model.canAdjustAudioDelay(by: -AudioDelay.step))
                    Button("Reset Audio Delay") { model.resetAudioDelay() }
                        .disabled(model.audioDelaySeconds == 0)
                }
            }
            CommandMenu("Subtitles") {
                if let model {
                    ForEach(subtitleMenuRows(model.subtitleTracks,
                                             selectedEngineIndex: model.selectedSubtitleIndex,
                                             isActive: model.isSubtitleActive)) { row in
                        Button(action: {
                            switch row.kind {
                            case .off: model.disableSubtitle()
                            case .track(let idx): model.selectSubtitle(engineIndex: idx)
                            }
                        }) {
                            Text((row.isSelected ? "\u{2713} " : "") + row.label)
                        }
                    }
                }
            }
            // Into the system Window menu, not next to it: a CommandMenu("Window") does not merge
            // with the menu AppKit already provides, it adds a second one under the same name.
            CommandGroup(after: .windowArrangement) {
                Toggle("Always on Top", isOn: $alwaysOnTop)
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Menu("Subtitle Size") {
                    if let model {
                        ForEach(SubtitleSize.allCases) { size in
                            Button(action: { model.setSubtitleSize(size) }) {
                                Text((model.subtitleSize == size ? "\u{2713} " : "") + size.label)
                            }
                        }
                    }
                }
            }
            StatsCommands()
            // Under Help because that is where someone goes when something is wrong. Both entries
            // exist so a report costs one drag or one save panel rather than a debugger.
            CommandGroup(after: .help) {
                Divider()
                Button("Reveal Diagnostics Log in Finder") {
                    DiagnosticsLog.shared.revealInFinder()
                }
                Button("Save Diagnostics Log\u{2026}") { saveDiagnosticsLog() }
            }
        }

        Window("Stats for Nerds", id: "stats") {
            Group {
                if let model {
                    StatsInspectorView(model: model)
                } else {
                    Text("No player.")
                }
            }
            // Sizes the window through .contentMinSize. Applied here rather than inside
            // StatsInspectorView because iOS mounts that same view as a player overlay.
            .frame(minWidth: 320, minHeight: 420)
        }
        .windowResizability(.contentMinSize)
        .defaultPosition(.topTrailing)
        // SwiftUI auto-adds a Window-menu item for every Window scene, using its title. That collided with the
        // explicit StatsCommands button (which carries the Cmd-Shift-I shortcut), showing "Stats for Nerds" twice.
        // commandsRemoved() drops the auto item so only the explicit, shortcut-bearing entry remains.
        .commandsRemoved()

        Window("Open Source Licenses", id: "licenses") {
            LicensesView()
        }
        .defaultSize(width: 860, height: 560)
        // App-menu button above is the entry point; drop the auto Window-menu item.
        .commandsRemoved()

        Settings {
            PlaybackSettingsView()
        }
    }

    private func openFile() {
        guard let model else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .matroska, .audio, .discImage]
        if panel.runModal() == .OK, let url = panel.url {
            Task { await model.open(url: url) }
        }
    }

    /// Save panel over a merged copy of the session logs, so the sandboxed build can put the file
    /// somewhere the user can attach it from.
    private func saveDiagnosticsLog() {
        guard let snapshot = DiagnosticsLog.shared.exportSnapshot() else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = snapshot.lastPathComponent
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: snapshot, to: destination)
    }

    private func openFolderPanel() {
        guard let model else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            let bm = BookmarkAccess.bookmark(for: url)
            Task { await model.openFolder(url, bookmarkData: bm) }
        }
    }
}

private struct StatsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Stats for Nerds") { openWindow(id: "stats") }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }
    }
}

extension UTType {
    /// ISO 9660 / UDF disc image (DVD / Blu-ray). Falls back to the `.iso` extension when the
    /// system UTI is unavailable, so the open panel and Finder association still work.
    static let discImage = UTType("public.iso-image") ?? UTType(filenameExtension: "iso") ?? .data
    /// Matroska video. The system does not reliably conform .mkv to public.movie in the open panel,
    /// so list it explicitly (paired with the UTImportedTypeDeclarations in the Info.plist) to
    /// un-gray .mkv files and let Finder associate the app.
    static let matroska = UTType("org.matroska.mkv") ?? UTType(filenameExtension: "mkv") ?? .movie
}
