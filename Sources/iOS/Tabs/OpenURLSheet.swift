import SwiftUI

struct OpenURLSheet: View {
    let model: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var openAsLive = false
    private var validURL: URL? { MediaURLValidation.normalized(text) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("https://example.com/video.mkv", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                // Skips the VOD probe pass (a live tuner pays two tune-ins otherwise).
                // Sources that resolved live once are remembered and load live automatically.
                Toggle("Live stream (tuner / IPTV)", isOn: $openAsLive)
            }
            .navigationTitle("Open URL")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Play") {
                        if let url = validURL {
                            Task { await model.open(url: url, forceLive: openAsLive) }
                            dismiss()
                        }
                    }.disabled(validURL == nil)
                }
            }
        }
    }
}
