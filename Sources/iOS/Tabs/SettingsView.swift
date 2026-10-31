import SwiftUI

struct SettingsView: View {
    @State private var diagnosticsSnapshot: DiagnosticsSnapshot?

    var body: some View {
        NavigationStack {
            PlaybackSettingsView {
                Section("Diagnostics") {
                    // The counterpart to the macOS Help-menu entries: a playback report costs one
                    // share sheet instead of a debugger.
                    Button {
                        diagnosticsSnapshot = DiagnosticsLog.shared.exportSnapshot()
                            .map(DiagnosticsSnapshot.init)
                    } label: {
                        Label("Share Diagnostics Log", systemImage: "doc.text.magnifyingglass")
                    }
                }
                Section {
                    // FFmpeg (LGPL) and the MIT/BSD components require their notices to ship with the app
                    // and be readable in it, on iOS as on the Mac.
                    NavigationLink {
                        LicensesView()
                    } label: {
                        Label("Open Source Licenses", systemImage: "doc.plaintext")
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .sheet(item: $diagnosticsSnapshot) { DiagnosticsShareSheet(url: $0.url) }
    }
}
