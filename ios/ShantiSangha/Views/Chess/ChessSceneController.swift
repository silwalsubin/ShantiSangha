import SceneKit
import SwiftUI
import Combine

/// 3D chess board (SceneKit). A perspective camera, a key directional light
/// that casts real shadows, code-generated pieces, and tap-to-move input.
/// Conforms to `ChessBoardRenderer` so the existing `ChessGameViewModel` drives
/// it unchanged.
///
/// First 3D pass — camera angle, lighting, and piece proportions are tuned by
/// eye on device (constants grouped below for easy adjustment).
final class ChessSceneController: NSObject, ChessBoardRenderer {

    // MARK: ChessBoardRenderer

    var onMoveSelected: ((ChessMove) -> Void)?
    var orientation: PieceColor = .white { didSet { rebuildPieces(); rebuildHighlights() } }
    var interactionColor: PieceColor?
    var isInteractionEnabled: Bool = true
    var reduceMotion: Bool = false

    /// Asks the host to choose a promotion piece; falls back to queen if unset.
    var onPromotionRequest: ((@escaping (PieceType) -> Void) -> Void)?

    let scnView = SCNView()

    // MARK: Scene graph

    private let scene = SCNScene()
    private let boardGroup = SCNNode()
    private let piecesNode = SCNNode()
    private let highlightsNode = SCNNode()

    // MARK: State

    private var position = ChessPosition.standard
    private var lastMove: ChessMove?
    private var pieceNodes: [Square: SCNNode] = [:]
    private var selection: Square?
    private var legalTargets: [Square: [ChessMove]] = [:]
    private var isAnimating = false

    private let tile: CGFloat = 1.0

    // MARK: Camera — pivots around the near (bottom) edge of the board and
    // always looks at it with a fixed downward shift, so that edge stays PINNED
    // on screen no matter the tilt. Dragging / device tilt only changes the
    // elevation (camera moves up/down). No horizontal spin, no zoom.
    // pivotNode (at near edge) → pitchNode (elevation) → cameraNode.
    private let pivotNode = SCNNode()
    private let pitchNode = SCNNode()
    private let cameraNode = SCNNode()
    private let nearEdgeZ: Float = 4.0     // world z of the board's near (white) edge
    private let cameraDistance: Float = 8.6 // smaller = closer = board fills more width
    private let cameraShift: Float = 0.18  // fixed tilt that drops the near edge toward the bottom
    private var camPitch: Float = 0.52     // elevation (radians); higher = more top-down
    private var motionPitch: Float = 0     // small additive tilt from device motion
    private let defaultPitch: Float = 0.52
    private let minPitch: Float = 0.30
    private let maxPitch: Float = 0.95
    private let motionPitchMax: Float = 0.05
    private var panLast: CGPoint = .zero

    override init() {
        super.init()
        configureView()
        buildEnvironment()
        rebuildPieces()
    }

    // MARK: Setup

    private func configureView() {
        scnView.scene = scene
        scnView.backgroundColor = .clear
        scene.background.contents = nil
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false
        scnView.isUserInteractionEnabled = true
        // Keep the render loop running so SCNActions (moves, pulses) animate.
        scnView.rendersContinuously = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tap)
        // One-finger vertical drag tilts the camera up/down. Tap (no movement)
        // still selects/moves, so they don't conflict.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        scnView.addGestureRecognizer(pan)
    }

    private func buildEnvironment() {
        scene.rootNode.addChildNode(boardGroup)
        boardGroup.addChildNode(piecesNode)
        boardGroup.addChildNode(highlightsNode)

        buildBoard()
        buildLights()
        buildCamera()
    }

    private func buildBoard() {
        // No wooden frame — just the 8×8 tiles, so the board itself fills more
        // of the screen. Tiles still receive the pieces' cast shadows.
        let light = UIColor(red: 0.92, green: 0.84, blue: 0.66, alpha: 1)
        let dark = UIColor(red: 0.55, green: 0.34, blue: 0.16, alpha: 1)
        for rank in 0..<8 {
            for file in 0..<8 {
                let isLight = (file + rank) % 2 == 1
                let geo = SCNBox(width: tile, height: 0.18, length: tile, chamferRadius: 0.0)
                geo.firstMaterial = constantWood(isLight ? light : dark, pbr: true)
                let node = SCNNode(geometry: geo)
                node.position = SCNVector3(Float(file) - 3.5, 0, Float(rank) - 3.5)
                node.castsShadow = false
                boardGroup.addChildNode(node)
            }
        }
    }

    private func buildLights() {
        let key = SCNLight()
        key.type = .directional
        key.intensity = 950
        key.color = UIColor(red: 1.0, green: 0.97, blue: 0.9, alpha: 1)
        key.castsShadow = true
        key.shadowMode = .forward
        key.shadowColor = UIColor(white: 0, alpha: 0.5)
        key.shadowSampleCount = 8
        key.shadowRadius = 5
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(4, 9, 5)
        keyNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 6, 0)
        scene.rootNode.addChildNode(keyNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 380
        ambient.color = UIColor(red: 0.85, green: 0.82, blue: 0.78, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Soft warm fill from the camera side so shadowed faces aren't black.
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 300
        fill.color = UIColor(red: 1.0, green: 0.9, blue: 0.75, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-Float.pi / 5, -Float.pi / 4, 0)
        scene.rootNode.addChildNode(fillNode)
    }

    private func buildCamera() {
        let camera = SCNCamera()
        // Horizontal projection so FOV controls width coverage in landscape.
        camera.fieldOfView = 50
        camera.projectionDirection = .horizontal
        camera.zNear = 0.1
        camera.zFar = 100
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, cameraDistance)
        // Fixed look-up shift drops the pinned near edge toward the bottom of
        // the screen (the camera looks slightly past the edge into the board).
        cameraNode.eulerAngles.x = cameraShift

        // pivot at the near edge; pitchNode rotates the rig around it. Because the
        // camera's pose is fixed within pitchNode, the near edge projects to the
        // same screen point for every elevation → it never moves.
        pivotNode.position = SCNVector3(0, 0, nearEdgeZ)
        pivotNode.addChildNode(pitchNode)
        pitchNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(pivotNode)
        applyCameraTransform(animated: false)
    }

    /// Device tilt nudges only the elevation (up/down). Roll (`x`) is ignored so
    /// the board never spins; the near edge stays pinned regardless.
    func setMotionTilt(x: Float, y: Float) {
        guard !reduceMotion else { motionPitch = 0; applyCameraTransform(animated: false); return }
        motionPitch = max(-1, min(1, y)) * motionPitchMax
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.12 // smooth out sensor jitter
        applyCameraTransform(animated: false)
        SCNTransaction.commit()
    }

    private func applyCameraTransform(animated: Bool) {
        let apply = { self.pitchNode.eulerAngles.x = -(self.camPitch + self.motionPitch) }
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.4
            apply()
            SCNTransaction.commit()
        } else {
            apply()
        }
    }

    /// Snap the elevation back to the default.
    func resetCamera() {
        camPitch = defaultPitch
        applyCameraTransform(animated: true)
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        let t = gr.translation(in: scnView)
        switch gr.state {
        case .began:
            panLast = t
        case .changed:
            let dy = Float(t.y - panLast.y)
            panLast = t
            // Vertical drag only: up → more overhead, down → flatter. No spin.
            camPitch = min(maxPitch, max(minPitch, camPitch - dy * 0.005))
            applyCameraTransform(animated: false)
        default:
            break
        }
    }

    private func constantWood(_ color: UIColor, pbr: Bool) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = pbr ? .physicallyBased : .constant
        m.diffuse.contents = color
        m.roughness.contents = 0.6
        m.metalness.contents = 0.0
        return m
    }

    // MARK: Geometry helpers

    private func point(for sq: Square) -> SCNVector3 {
        let f = orientation == .white ? sq.file : 7 - sq.file
        let r = orientation == .white ? sq.rank : 7 - sq.rank
        return SCNVector3(Float(f) - 3.5, 0.09, 3.5 - Float(r))
    }

    private func square(atWorld p: SCNVector3) -> Square? {
        let f = Int((p.x + 3.5).rounded())
        let r = Int((3.5 - p.z).rounded())
        guard (0...7).contains(f), (0...7).contains(r) else { return nil }
        let file = orientation == .white ? f : 7 - f
        let rank = orientation == .white ? r : 7 - r
        return Square(file: file, rank: rank)
    }

    // MARK: Public API (ChessBoardRenderer)

    func show(_ newPosition: ChessPosition, animating execution: MoveExecution?, lastMove move: ChessMove?) {
        clearSelectionState()
        if let execution, !reduceMotion {
            animate(execution) { [weak self] in
                guard let self else { return }
                self.position = newPosition
                self.lastMove = move ?? execution.move
                self.rebuildPieces()
                self.rebuildHighlights()
            }
        } else {
            position = newPosition
            lastMove = move ?? execution?.move
            rebuildPieces()
            rebuildHighlights()
        }
    }

    // MARK: Rebuild

    private func rebuildPieces() {
        piecesNode.childNodes.forEach { $0.removeFromParentNode() }
        pieceNodes.removeAll()
        for sq in Square.allSquares {
            guard let piece = position.piece(at: sq) else { continue }
            let node = ChessPieces3D.node(for: piece.type, isWhite: piece.color == .white)
            node.position = point(for: sq)
            // Pieces are modelled facing +z; the knight should face the
            // opposition (the far side). The near side for this orientation is
            // the side whose color matches `orientation`, so flip those 180°.
            if piece.color == orientation { node.eulerAngles.y = .pi }
            piecesNode.addChildNode(node)
            pieceNodes[sq] = node
        }
    }

    private func rebuildHighlights() {
        highlightsNode.childNodes.forEach { $0.removeFromParentNode() }

        if let lastMove {
            for sq in [lastMove.from, lastMove.to] {
                highlightsNode.addChildNode(planeHighlight(at: sq, color: UIColor.sacredGoldLightUI.withAlphaComponent(0.32)))
            }
        }
        if let king = position.kingSquare(position.sideToMove), position.isInCheck {
            let node = planeHighlight(at: king, color: UIColor.sacredRedUI.withAlphaComponent(0.55))
            node.runAction(.repeatForever(.sequence([
                .fadeOpacity(to: 0.25, duration: 0.6),
                .fadeOpacity(to: 0.6, duration: 0.6)
            ])))
            highlightsNode.addChildNode(node)
        }
        if let selection {
            highlightsNode.addChildNode(planeHighlight(at: selection, color: UIColor.sacredGoldUI.withAlphaComponent(0.45)))
            for (target, _) in legalTargets {
                let isCapture = position.piece(at: target) != nil || target == position.enPassant
                highlightsNode.addChildNode(legalMarker(at: target, isCapture: isCapture))
            }
        }
    }

    private func planeHighlight(at sq: Square, color: UIColor) -> SCNNode {
        let plane = SCNPlane(width: tile * 0.98, height: tile * 0.98)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        plane.firstMaterial = m
        let node = SCNNode(geometry: plane)
        var p = point(for: sq); p.y = 0.095
        node.position = p
        node.eulerAngles.x = -Float.pi / 2
        node.renderingOrder = 5
        return node
    }

    private func legalMarker(at sq: Square, isCapture: Bool) -> SCNNode {
        let geo: SCNGeometry = isCapture
            ? SCNTorus(ringRadius: tile * 0.42, pipeRadius: 0.035)
            : SCNCylinder(radius: 0.12, height: 0.03)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.sacredGoldUI.withAlphaComponent(0.75)
        geo.firstMaterial = m
        let node = SCNNode(geometry: geo)
        var p = point(for: sq); p.y = 0.12
        node.position = p
        node.runAction(.repeatForever(.sequence([
            .scale(to: 1.18, duration: 0.7), .scale(to: 1.0, duration: 0.7)
        ])))
        return node
    }

    // MARK: Animation

    private func animate(_ execution: MoveExecution, completion: @escaping () -> Void) {
        isAnimating = true
        let duration = 0.32

        if let capSq = execution.capturedSquare, let capNode = pieceNodes[capSq] {
            let vanish = SCNAction.group([.fadeOut(duration: duration * 0.7),
                                          .scale(to: 0.2, duration: duration * 0.7)])
            capNode.runAction(.sequence([vanish, .removeFromParentNode()]))
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        if let mover = pieceNodes[execution.move.from] {
            // Cancel any in-flight lift/settle so the glide doesn't fight it.
            mover.removeAllActions()
            mover.position = point(for: execution.move.from)
            // Lift, glide, settle — a little arc reads as a real piece move.
            let dest = point(for: execution.move.to)
            let up = SCNAction.moveBy(x: 0, y: 0.35, z: 0, duration: duration * 0.3)
            up.timingMode = .easeOut
            let over = SCNAction.move(to: SCNVector3(dest.x, 0.44, dest.z), duration: duration * 0.4)
            over.timingMode = .easeInEaseOut
            let down = SCNAction.move(to: dest, duration: duration * 0.3)
            down.timingMode = .easeIn
            mover.runAction(.sequence([up, over, down]))
        }

        if let rf = execution.rookFrom, let rt = execution.rookTo, let rook = pieceNodes[rf] {
            rook.runAction(.move(to: point(for: rt), duration: duration))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
            self?.isAnimating = false
            completion()
        }
    }

    // MARK: Input

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        guard isInteractionEnabled, !isAnimating else { return }
        let p = gr.location(in: scnView)
        let hits = scnView.hitTest(p, options: [.boundingBoxOnly: false])
        guard let hit = hits.first, let sq = square(atWorld: hit.worldCoordinates) else { return }
        handleBoardTap(sq)
    }

    private func handleBoardTap(_ sq: Square) {
        if let from = selection {
            if let moves = legalTargets[sq], let first = moves.first {
                if moves.count > 1, first.promotion != nil {
                    requestPromotion(from: from, to: sq)
                } else {
                    clearSelectionState(); rebuildHighlights()
                    onMoveSelected?(first)
                }
                return
            }
            if canSelect(sq) { select(sq) } else { clearSelectionState(); rebuildHighlights() }
        } else if canSelect(sq) {
            select(sq)
        }
    }

    private func canSelect(_ sq: Square) -> Bool {
        guard let piece = position.piece(at: sq), piece.color == position.sideToMove else { return false }
        if let interactionColor, piece.color != interactionColor { return false }
        return true
    }

    private func select(_ sq: Square) {
        if let prev = selection { pieceNodes[prev]?.runAction(.move(to: point(for: prev), duration: 0.12)) }
        selection = sq
        legalTargets = [:]
        for move in position.legalMoves(from: sq) {
            legalTargets[move.to, default: []].append(move)
        }
        // Lift the selected piece for a tactile cue.
        if let node = pieceNodes[sq] {
            var up = point(for: sq); up.y = 0.42
            node.runAction(.move(to: up, duration: 0.14))
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        rebuildHighlights()
    }

    private func clearSelectionState() {
        if let sel = selection, let node = pieceNodes[sel] {
            node.runAction(.move(to: point(for: sel), duration: 0.12))
        }
        selection = nil
        legalTargets = [:]
    }

    private func requestPromotion(from: Square, to: Square) {
        let emit: (PieceType) -> Void = { [weak self] type in
            guard let self else { return }
            self.clearSelectionState(); self.rebuildHighlights()
            self.onMoveSelected?(ChessMove(from: from, to: to, promotion: type))
        }
        if let onPromotionRequest {
            onPromotionRequest(emit)
        } else {
            emit(.queen)
        }
    }
}

// MARK: - SwiftUI host + holder

/// Owns the controller (stable across redraws) and surfaces a pending promotion
/// choice to SwiftUI.
@MainActor
final class ChessSceneHolder: ObservableObject {
    let controller = ChessSceneController()
    @Published var promotion: PromotionPrompt?
    private var motionCancellables = Set<AnyCancellable>()

    init() {
        controller.onPromotionRequest = { [weak self] complete in
            self?.promotion = PromotionPrompt { piece in
                complete(piece)
                self?.promotion = nil
            }
        }
    }

    /// Begin feeding device tilt into the camera parallax (reuses the app's
    /// shared CoreMotion manager). Balanced by `stopMotion()`.
    func startMotion() {
        guard motionCancellables.isEmpty else { return }
        MotionManager.shared.start()
        MotionManager.shared.$shineX
            .combineLatest(MotionManager.shared.$shineY)
            .sink { [weak controller] roll, pitch in
                controller?.setMotionTilt(x: Float(roll), y: Float(pitch))
            }
            .store(in: &motionCancellables)
    }

    func stopMotion() {
        guard !motionCancellables.isEmpty else { return }
        motionCancellables.removeAll()
        MotionManager.shared.stop()
        controller.setMotionTilt(x: 0, y: 0)
    }
}

struct PromotionPrompt: Identifiable {
    let id = UUID()
    let complete: (PieceType) -> Void
}

struct ChessSceneView: UIViewRepresentable {
    let controller: ChessSceneController
    func makeUIView(context: Context) -> SCNView { controller.scnView }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - Color bridges

private extension UIColor {
    static let sacredGoldUI = UIColor(SwiftUI.Color.sacredGold)
    static let sacredGoldLightUI = UIColor(SwiftUI.Color.sacredGoldLight)
    static let sacredRedUI = UIColor(SwiftUI.Color.sacredRed)
}
