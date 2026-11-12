import AetherEngine
import AVKit

// MARK: - AVPlayerViewControllerDelegate (Picture in Picture)

/// AVKit-native auto-PiP handoff. No custom PiP button and no manual
/// `AVPictureInPictureController`; AVKit drives PiP directly off this delegate
/// when the user swipes Home during playback.
///
/// `nonisolated`: with Swift 6 + InferIsolatedConformances a plain `func` here
/// would silently inherit MainActor isolation from the class, which trips
/// `_dispatch_assert_queue_fail` if AVKit invokes the selector off-main before
/// the isolation check runs. Declaring `nonisolated` and hopping via
/// `Task { @MainActor }` keeps all `model`/`pipActive` access on the actor
/// while satisfying the (nonisolated) protocol requirement AVKit expects.
extension PlayerHostController: AVPlayerViewControllerDelegate {
    // Keep the player presented when PiP starts (the default dismisses it, so
    // returning from PiP would land back on the presenting view instead of
    // restoring fullscreen).
    nonisolated func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(
        _ playerViewController: AVPlayerViewController
    ) -> Bool {
        false
    }

    // `pipActive` is set synchronously (before PiP dismisses this VC) so
    // viewWillDisappear can distinguish a PiP handoff from a real teardown.
    nonisolated func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        pipActive = true
        Task { @MainActor [weak self] in self?.model.engine.pictureInPictureActive = true }
    }

    nonisolated func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        // Reset the latch synchronously (mirrors willStart). Without this, pipActive stays true
        // after a normal PiP stop and viewWillDisappear's `!pipActive` guard would skip model.stop()
        // on the next real dismissal, leaking the engine session.
        pipActive = false
        Task { @MainActor [weak self] in self?.model.engine.pictureInPictureActive = false }
    }

    nonisolated func playerViewController(
        _ playerViewController: AVPlayerViewController,
        failedToStartPictureInPictureWithError error: any Error
    ) {
        Task { @MainActor [weak self] in self?.pipActive = false }
    }
}

// MARK: - Software path (AetherEngine#1046)

/// The software path (interlaced H.264, VP9, AV1 without HW decode, ...) has no AVPlayer, so
/// AVKit's PiP above never sees it. This arms the same swipe-Home PiP on the engine's
/// sample-buffer layer instead.
extension PlayerHostController {
    /// A new source is a new session with a new layer, so the controller is rebuilt every time.
    /// The engine closes an open window itself when the old session ends.
    func bindSoftwarePiP(_ source: SoftwarePiPSource?) {
        softwarePiP?.delegate = nil
        softwarePiP = nil
        guard let source, let pip = source.makePictureInPictureController() else { return }
        pip.delegate = softwarePiPDelegate
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        softwarePiP = pip
    }
}

/// Delegate for the software PiP controller. A separate object on purpose: AVPlayerViewController
/// may answer these selectors privately for its own PiP, and the host subclassing it must not
/// override them.
final class SoftwarePiPDelegate: NSObject, AVPictureInPictureControllerDelegate {
    weak var host: PlayerHostController?

    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        // Synchronous, like the AVKit path: viewWillDisappear reads it during the handoff.
        host?.pipActive = true
        Task { @MainActor [weak host] in host?.model.engine.pictureInPictureActive = true }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        host?.pipActive = false
        Task { @MainActor [weak host] in host?.model.engine.pictureInPictureActive = false }
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Error
    ) {
        host?.pipActive = false
        Task { @MainActor [weak host] in host?.model.engine.pictureInPictureActive = false }
    }

    // The player stays presented under the window, so there is nothing to bring back.
    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
