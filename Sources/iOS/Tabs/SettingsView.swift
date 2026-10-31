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
            }
            .navigationTitle("Settings")
        }
        .sheet(item: $diagnosticsSnapshot) { DiagnosticsShareSheet(url: $0.url) }
    }
}
