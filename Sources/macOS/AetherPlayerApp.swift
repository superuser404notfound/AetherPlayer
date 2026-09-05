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
            CommandMenu("Audio") {
                if let model {
                    ForEach(audioMenuRows(model.audioTracks, activeIndex: model.activeAudioTrackIndex)) { row in
                        Button(action: { model.selectAudio(engineIndex: row.engineIndex) }) {
                            Text((row.isSelected ? "\u{2713} " : "") + row.label)
                        }
                    }
                    Divider()
                    // The keys J and K do the same thing on the video surface (KeyCatcherView), which is
                    // where the other single-key transport lives. They are deliberately not menu key
                    // equivalents: a bare letter as a menu shortcut fires from a text field too, and this
                    // app has one in the Open URL sheet.
                    Menu("Audio Delay") {
                        Button("Delay Audio (+\(Int(AudioDelay.step * 1000)) ms)") {
                            model.adjustAudioDelay(by: AudioDelay.step)
                        }
                        .disabled(!model.canAdjustAudioDelay(by: AudioDelay.step))
                        Button("Advance Audio (-\(Int(AudioDelay.step * 1000)) ms)") {
                            model.adjustAudioDelay(by: -AudioDelay.step)
                        }
                        .disabled(!model.canAdjustAudioDelay(by: -AudioDelay.step))
                        Divider()
                        Button("Reset to 0 ms") { model.resetAudioDelay() }
                            .disabled(model.audioDelaySeconds == 0)
                    }
                    // The current value as its own row rather than folded into a title: the submenu has to
                    // be opened to read a value carried in its items, and this is the one number a viewer
                    // is nudging by ear and wants to see without navigating.
                    Text("Audio delay: \(AudioDelay.label(model.audioDelaySeconds))")
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
                    Text("No player.").frame(minWidth: 320, minHeight: 420)
                }
            }
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
            PreferencesView()
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

/// Preferences window (Cmd-,). The forward-buffer depth and the Dolby Vision experiment; a home for
/// future settings.
private struct PreferencesView: View {
    // 0 == Auto (engine default); otherwise a forward-buffer segment count
    // (AetherEngine #102, engine clamps to 4...150). Applied on the next open.
    @AppStorage("playback.forwardBufferSegments") private var forwardBufferSegments = 0
    // AetherEngine AE#455. Applied on the next open, like the buffer depth above.
    @AppStorage("playback.forceDolbyVisionOnNonDVDisplay") private var forceDolbyVision = false

    var body: some View {
        Form {
            Picker("Forward buffer", selection: $forwardBufferSegments) {
                Text("Auto").tag(0)
                Text("Small (8 segments)").tag(8)
                Text("Default (30 segments)").tag(30)
                Text("Large (60 segments)").tag(60)
                Text("Maximum (120 segments)").tag(120)
            }
            Text("How far ahead to buffer. Higher values help slow or unstable sources at the cost of memory, and apply to the next file you open.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Toggle("Compose Dolby Vision on this display", isOn: $forceDolbyVision)
            Text("Experimental. No Mac reports a Dolby Vision display, so a Profile 8.1 source plays as its HDR10 base layer and the per-frame metadata is discarded. This hands the composition to AVPlayer instead. On a display without the headroom for it, expect a shifted or washed-out picture; turn it back off and reopen the file. Applies to the next file you open.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 440)
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
