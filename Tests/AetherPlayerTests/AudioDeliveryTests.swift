import Testing
import AetherEngine
@testable import AetherPlayer

/// How the engine's `audioDelivery` fact (AE#462) is read: what the Stats row says, and which of the
/// seven values is worth interrupting the viewer over.
struct AudioDeliveryTests {

    @Test func everyDeliveryHasALabelAndNoneIsBlank() {
        for delivery in AudioDelivery.allCases {
            let label = formatAudioDelivery(delivery)
            #expect(!label.isEmpty)
            // The figure-dash placeholder is reserved for "no session yet", not for a session whose
            // delivery is known. A new engine case landing here would otherwise arrive as a dash.
            if delivery != .none {
                #expect(label != "\u{2012}", "\(delivery.rawValue) has no label of its own")
            }
        }
    }

    @Test func labelsNameThePipeline() {
        #expect(formatAudioDelivery(.streamCopy) == "Bitstream")
        #expect(formatAudioDelivery(.bridged) == "Bridged")
        #expect(formatAudioDelivery(.droppedNoPipeline) == "Dropped (no decoder)")
        #expect(formatAudioDelivery(.none) == "\u{2012}")
    }

    /// Only the drop is a problem. A source that carries no audio is silent by authorship, and warning
    /// about that would put a banner on every silent film and every screen recording without sound.
    @Test func onlyTheDropWarns() {
        #expect(PlayerNotice.forAudioDelivery(.droppedNoPipeline)?.kind == .warning)
        for delivery in AudioDelivery.allCases where delivery != .droppedNoPipeline {
            #expect(PlayerNotice.forAudioDelivery(delivery) == nil, "\(delivery.rawValue) should not warn")
        }
    }

    /// Two notices with the same text are two notices: the id is what restarts the on-screen timer, so
    /// a second drop after a reload is not swallowed as a duplicate of the first.
    @Test func noticesAreDistinctEvenWithIdenticalText() {
        let first = PlayerNotice.forAudioDelivery(.droppedNoPipeline)
        let second = PlayerNotice.forAudioDelivery(.droppedNoPipeline)
        #expect(first?.text == second?.text)
        #expect(first != second)
    }
}
