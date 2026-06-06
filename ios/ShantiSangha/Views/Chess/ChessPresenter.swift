import SwiftUI
import UIKit

/// A hosting controller that only supports landscape. When presented, iOS
/// rotates it during the presentation animation — so the chess screen is
/// landscape from its first frame (no portrait flash).
final class LandscapeHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var shouldAutorotate: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
}

/// Presents the Chess screen full-screen in forced landscape, and restores
/// portrait on dismiss. Used instead of a navigation push so chess never
/// appears in portrait.
enum ChessPresenter {
    /// Solo (vs the app / pass-and-play).
    static func present() {
        present { close in ChessGameView(onClose: close) }
    }

    /// Friend game over the network (channel = friendship id).
    static func presentFriend(friendshipId: UUID, friendUserId: UUID) {
        let friend = ChessGameViewModel.FriendGame(friendshipId: friendshipId, friendUserId: friendUserId)
        present { close in ChessGameView(friend: friend, onClose: close) }
    }

    private static func present<Content: View>(@ViewBuilder content: (@escaping () -> Void) -> Content) {
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }

        // Allow landscape app-wide while chess is up; the controller itself only
        // supports landscape, so the app rotates to landscape for it and the
        // (portrait) screens underneath stay covered.
        AppDelegate.orientationLock = .allButUpsideDown

        weak var weakHost: UIViewController?
        let close: () -> Void = {
            AppDelegate.orientationLock = .portrait      // rotate back to portrait
            weakHost?.dismiss(animated: true)
        }

        let host = LandscapeHostingController(rootView: NavigationStack { content(close) })
        host.modalPresentationStyle = .fullScreen
        weakHost = host
        top.present(host, animated: true)
    }
}
