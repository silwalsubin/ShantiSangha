import SwiftUI

/// The chess board screen — full-screen and immersive (tab bar hidden). The
/// mode chips (Gentle / Measured / Sharp / 2 Players) live right here, so there
/// is no separate hub: Home opens straight into the game.
struct ChessGameView: View {
    @StateObject private var vm: ChessGameViewModel
    @StateObject private var holder = ChessSceneHolder()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Dismisses the (modally presented) landscape chess screen.
    var onClose: (() -> Void)?
    private let isFriendGame: Bool

    /// Solo (vs the app / pass-and-play).
    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        self.isFriendGame = false
        _vm = StateObject(wrappedValue: ChessGameViewModel())
    }

    /// Friend game over the network.
    init(friend: ChessGameViewModel.FriendGame, onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        self.isFriendGame = true
        _vm = StateObject(wrappedValue: ChessGameViewModel(friend: friend))
    }

    var body: some View {
        ZStack {
            SacredBackground().ignoresSafeArea()

            // Board fills the whole screen.
            ChessSceneView(controller: holder.controller)
                .ignoresSafeArea()
                .accessibilityLabel("Chess board")

            // Custom, fully transparent top bar floating over the board.
            VStack(spacing: 0) {
                topBar
                Spacer()
            }

            if vm.isGameOver {
                gameOverOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            if let promotion = holder.promotion {
                promotionOverlay(promotion)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.isGameOver)
        .animation(.easeInOut(duration: 0.2), value: holder.promotion?.id)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .onAppear {
            holder.controller.reduceMotion = reduceMotion
            vm.attach(renderer: holder.controller)
            if !reduceMotion { holder.startMotion() }
        }
        .onDisappear {
            holder.stopMotion()
            vm.teardown()
        }
        .onChange(of: reduceMotion) { _, newValue in
            holder.controller.reduceMotion = newValue
            if newValue { holder.stopMotion() } else { holder.startMotion() }
        }
    }

    /// Floating, fully transparent top bar: back · status (centered) · menu.
    private var topBar: some View {
        ZStack {
            statusBar
            HStack {
                Button { onClose?() } label: { circleIcon("chevron.left") }
                    .buttonStyle(.plain)
                Spacer()
                optionsMenu
            }
        }
        .padding(.horizontal, SacredSpacing.m)
        .padding(.top, SacredSpacing.xs)
    }

    /// A gold glyph inside a soft dark circle — the shared chrome for the
    /// floating back / menu buttons.
    private func circleIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold, design: .serif))
            .foregroundColor(.sacredGold)
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.black.opacity(0.28)))
            .overlay(Circle().stroke(Color.sacredGold.opacity(0.4), lineWidth: 1))
    }

    /// Live status, shown centered in the floating top bar.
    private var statusBar: some View {
        HStack(spacing: SacredSpacing.xs) {
            if vm.isOpponentThinking {
                ProgressView().tint(.sacredGold).scaleEffect(0.7)
            }
            Text(vm.statusText)
                .font(.sacredSubheading)
                .foregroundColor(vm.position.isInCheck ? .sacredRed : .sacredText)
                .animation(.easeInOut(duration: 0.2), value: vm.statusText)
        }
    }

    private func promotionOverlay(_ prompt: PromotionPrompt) -> some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: SacredSpacing.m) {
                Text("Promote to")
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
                HStack(spacing: SacredSpacing.m) {
                    ForEach([PieceType.queen, .rook, .bishop, .knight], id: \.self) { type in
                        Button {
                            prompt.complete(type)
                        } label: {
                            Text(promotionGlyph(type))
                                .font(.system(size: 44, design: .serif))
                                .foregroundColor(.sacredText)
                                .frame(width: 56, height: 56)
                                .background(Circle().fill(Color.sacredGold.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(SacredSpacing.l)
            .background(
                RoundedRectangle(cornerRadius: SacredRadius.lux)
                    .fill(Color.sacredBgCard)
                    .overlay(RoundedRectangle(cornerRadius: SacredRadius.lux)
                        .stroke(Color.sacredGold.opacity(0.3), lineWidth: 1))
            )
            .sacredCardShadow()
        }
    }

    private func promotionGlyph(_ type: PieceType) -> String {
        switch type {
        case .queen: return "\u{265B}\u{FE0E}"
        case .rook: return "\u{265C}\u{FE0E}"
        case .bishop: return "\u{265D}\u{FE0E}"
        case .knight: return "\u{265E}\u{FE0E}"
        default: return "\u{265B}\u{FE0E}"
        }
    }

    /// All the options tucked into a single quiet menu so the board stays the
    /// focus: choose opponent / difficulty, start a new game, or undo.
    private var optionsMenu: some View {
        Menu {
            if isFriendGame {
                Section {
                    Button(role: .destructive) {
                        vm.resign()
                    } label: {
                        Label("Resign", systemImage: "flag")
                    }
                    .disabled(vm.isGameOver)
                    Button {
                        vm.newGame()
                    } label: {
                        Label("New game", systemImage: "arrow.clockwise")
                    }
                }
            } else {
                Picker("Opponent", selection: opponentBinding) {
                    ForEach(ChessMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Section {
                    Button {
                        vm.newGame()
                    } label: {
                        Label("New game", systemImage: "arrow.clockwise")
                    }
                    Button {
                        vm.undo()
                    } label: {
                        Label("Undo move", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!vm.canUndo)
                }
            }
            Section {
                Button {
                    holder.controller.resetCamera()
                } label: {
                    Label("Reset view", systemImage: "arrow.counterclockwise.circle")
                }
            }
        } label: {
            circleIcon("ellipsis")
        }
    }

    private var opponentBinding: Binding<ChessMode> {
        Binding(get: { vm.mode }, set: { vm.select(mode: $0) })
    }

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture {} // swallow taps behind the card

            VStack(spacing: SacredSpacing.l) {
                Text(gameOverHeadline)
                    .font(.sacredHero)
                    .foregroundColor(.sacredGold)
                    .multilineTextAlignment(.center)
                Text(vm.statusText)
                    .font(.sacredBody)
                    .foregroundColor(.sacredTextSecondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: SacredSpacing.s) {
                    SacredPrimaryButton("Rematch", icon: "arrow.clockwise", style: .commit) {
                        vm.newGame()
                    }
                    Button("Leave") { onClose?() }
                        .font(.sacredButtonLabel)
                        .foregroundColor(.sacredMuted)
                }
            }
            .padding(SacredSpacing.l)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: SacredRadius.lux)
                    .fill(Color.sacredBgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: SacredRadius.lux)
                            .stroke(Color.sacredGold.opacity(0.3), lineWidth: 1)
                    )
            )
            .sacredCardShadow()
            .padding(.horizontal, SacredSpacing.xl)
        }
    }

    private var gameOverHeadline: String {
        guard let result = vm.result else { return "" }
        switch result {
        case .checkmate(let winner):
            if vm.isHotSeat { return "\(winner == .white ? "White" : "Black") wins" }
            return winner == vm.humanColor ? "You win" : "You lose"
        case .stalemate, .drawInsufficientMaterial, .drawFiftyMove, .drawRepetition:
            return "A draw"
        }
    }
}
