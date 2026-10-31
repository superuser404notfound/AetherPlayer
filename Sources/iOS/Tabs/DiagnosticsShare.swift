import SwiftUI
import UIKit

/// Share sheet over a merged copy of the session logs. The snapshot is written once, when the user
/// asks for it, rather than on every render: it copies the whole log.
struct DiagnosticsShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// `URL` is not `Identifiable`, and `sheet(item:)` needs it to be.
struct DiagnosticsSnapshot: Identifiable {
    let id = UUID()
    let url: URL
}
