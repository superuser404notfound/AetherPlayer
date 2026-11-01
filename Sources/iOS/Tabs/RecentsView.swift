import SwiftUI

struct RecentsView: View {
    let model: PlayerViewModel
    @State private var confirmingClear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                RecentsGrid(model: model)
            }
            .navigationTitle("Recents")
            .toolbar {
                if !model.recents.items.isEmpty {
                    Button("Clear", role: .destructive) { confirmingClear = true }
                        .confirmationDialog("Clear the playback history?", isPresented: $confirmingClear) {
                            Button("Clear History", role: .destructive) { PlaybackHistory.clear() }
                        } message: {
                            Text("Removes the recent files, their resume points and thumbnails. The files themselves are not touched.")
                        }
                }
            }
        }
    }
}
