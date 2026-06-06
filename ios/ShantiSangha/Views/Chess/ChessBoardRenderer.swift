import Foundation

/// What the `ChessGameViewModel` needs from a board view, so it doesn't care
/// whether the board is rendered in 2D (SpriteKit) or 3D (SceneKit).
/// `ChessSceneController` (3D) is the live implementation.
protocol ChessBoardRenderer: AnyObject {
    /// Fired when the user completes a legal move (promotion already resolved).
    var onMoveSelected: ((ChessMove) -> Void)? { get set }
    /// Which side is drawn nearest the camera / at the bottom.
    var orientation: PieceColor { get set }
    /// Restrict which color the human may move (nil = either side, hot-seat).
    var interactionColor: PieceColor? { get set }
    /// When false, taps are ignored (AI thinking / game over).
    var isInteractionEnabled: Bool { get set }
    /// Snap instead of animate (Reduce Motion).
    var reduceMotion: Bool { get set }
    /// Display a position; animate the transition when `execution` is provided.
    func show(_ position: ChessPosition, animating execution: MoveExecution?, lastMove: ChessMove?)
}
