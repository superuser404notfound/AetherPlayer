import SwiftUI
import UIKit

/// Two-finger trackpad swipe (Magic Keyboard, any pointer with continuous scroll), the way Quick Look
/// scrubs in Files. Recognizes scroll events only, never touches, so it cannot compete with the tap,
/// double-tap and edge-swipe gestures. A swipe that starts vertical is ignored until it ends.
struct TrackpadScrubGesture: UIGestureRecognizerRepresentable {
    let onEvent: (TrackpadScrubEvent) -> Void

    final class Coordinator { var horizontal: Bool? }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.allowedScrollTypesMask = .continuous
        pan.allowedTouchTypes = []
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let coordinator = context.coordinator
        switch pan.state {
        case .began, .changed:
            let translation = pan.translation(in: pan.view)
            if coordinator.horizontal == nil, translation != .zero {
                coordinator.horizontal = abs(translation.x) > abs(translation.y)
            }
            if coordinator.horizontal == true { onEvent(.moved(translationX: translation.x)) }
        case .ended:
            if coordinator.horizontal == true { onEvent(.ended) }
            coordinator.horizontal = nil
        case .cancelled, .failed:
            if coordinator.horizontal == true { onEvent(.cancelled) }
            coordinator.horizontal = nil
        default:
            break
        }
    }
}
