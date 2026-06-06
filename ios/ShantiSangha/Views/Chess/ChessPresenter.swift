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
    static func present() {
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

        let content = NavigationStack { ChessGameView(onClose: close) }
        let host = LandscapeHostingController(rootView: content)
        host.modalPresentationStyle = .fullScreen
        weakHost = host
        top.present(host, animated: true)
    }
}
