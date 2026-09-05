import Foundation
import AetherEngine

/// A short line shown over the picture and then withdrawn: the lip-sync nudge's new value, or the
/// fact that a source's audio never reached the renderer.
///
/// It carries its own id so that two notices with the same text still restart the on-screen timer,
/// and its own duration because the two kinds are not read the same way: a value you just changed
/// yourself is a confirmation and can go quickly, a fact you did not ask for has to survive a glance
/// away from the screen.
struct PlayerNotice: Identifiable, Equatable {

    enum Kind: Equatable {
        /// Confirms something the viewer just did.
        case info
        /// States something about the session the viewer did not ask about and cannot fix from here.
        case warning
    }

    let id = UUID()
    let text: String
    let kind: Kind
    let seconds: Double

    init(_ text: String, kind: Kind = .info) {
        self.text = text
        self.kind = kind
        self.seconds = kind == .warning ? 6 : 2.5
    }

    /// The line for a session whose audio was dropped, or nil for every delivery that is merely a
    /// description of a healthy session.
    ///
    /// Only `.droppedNoPipeline` earns a notice. `.noAudioInSource` is silence the source authored,
    /// and announcing it would put a warning on every silent film and every video someone exported
    /// without a track; the remaining values all describe audio that arrived.
    static func forAudioDelivery(_ delivery: AudioDelivery) -> PlayerNotice? {
        guard delivery == .droppedNoPipeline else { return nil }
        return PlayerNotice("No audio: this source's audio could not be decoded, the video plays silently.",
                            kind: .warning)
    }
}
