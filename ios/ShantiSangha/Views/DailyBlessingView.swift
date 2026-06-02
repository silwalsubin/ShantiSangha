import SwiftUI
import UIKit

/// A once-a-day spiritual blessing, shown the first time the app reaches
/// the main experience on a new day. It opens like the title card of a
/// film — a lamp warms to life, a line of wisdom rises, then the whole
/// thing dissolves to reveal the app waiting behind it.
///
/// Local quotes mean it paints instantly: no spinner, no network. Tap
/// anywhere to begin early, or let it pass on its own. Honors Reduce
/// Motion by collapsing every move to a soft cross-fade.
struct DailyBlessingView: View {
    let quote: DailyQuote
    let onDismiss: () -> Void

    @State private var glow = false
    @State private var iconIn = false
    @State private var quoteIn = false
    @State private var sourceIn = false
    @State private var hintIn = false
    @State private var dismissing = false
    @State private var autoDismiss: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Warm parchment, deepened a touch at the edges so the lamp
            // reads as the one source of light on screen.
            SacredBackground()
                .overlay(
                    RadialGradient(
                        colors: [.clear, Color.sacredText.opacity(0.06)],
                        center: .center,
                        startRadius: 160,
                        endRadius: 520
                    )
                )
                .ignoresSafeArea()

            VStack(spacing: SacredSpacing.l) {
                Spacer()

                lamp

                Text(quote.text)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundColor(.sacredText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SacredSpacing.l)
                    .opacity(quoteIn ? 1 : 0)
                    .offset(y: quoteIn ? 0 : 14)

                Text(quote.source)
                    .font(.sacredSectionLabel)
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundColor(.sacredLabel)
                    .opacity(sourceIn ? 1 : 0)

                Spacer()
                Spacer()

                Text("Tap to begin")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
                    .opacity(hintIn ? 0.7 : 0)
                    .padding(.bottom, SacredSpacing.xl)
            }
        }
        .opacity(dismissing ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .task { await runIntro() }
        .onDisappear { autoDismiss?.cancel() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(quote.text). \(quote.source). Double-tap to begin.")
    }

    // MARK: - Lamp

    private var lamp: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.sacredGoldShine.opacity(glow ? 0.32 : 0.14),
                            .clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: glow ? 92 : 68
                    )
                )
                .frame(width: 190, height: 190)
                .blur(radius: 6)

            SacredIconView(icon: .diya, size: 58)
                .foregroundColor(.sacredGold)
        }
        .scaleEffect(iconIn ? 1 : 0.82)
        .opacity(iconIn ? 1 : 0)
    }

    // MARK: - Choreography

    @MainActor
    private func runIntro() async {
        withAnimation(SacredMotion.respecting(SacredMotion.morph)) { iconIn = true }
        // Breathing glow — toggling once kicks off the repeating loop.
        withAnimation(SacredMotion.respecting(SacredMotion.breathing)) { glow = true }

        try? await Task.sleep(nanoseconds: 450_000_000)
        withAnimation(SacredMotion.respecting(SacredMotion.rise)) { quoteIn = true }

        try? await Task.sleep(nanoseconds: 520_000_000)
        withAnimation(SacredMotion.respecting(SacredMotion.veil)) { sourceIn = true }

        try? await Task.sleep(nanoseconds: 900_000_000)
        withAnimation(SacredMotion.respecting(SacredMotion.veil)) { hintIn = true }

        autoDismiss = Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { dismiss() }
        }
    }

    @MainActor
    private func dismiss() {
        guard !dismissing else { return }
        autoDismiss?.cancel()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(SacredMotion.respecting(SacredMotion.dismiss)) { dismissing = true }
        Task {
            try? await Task.sleep(nanoseconds: 320_000_000)
            await MainActor.run { onDismiss() }
        }
    }
}

// MARK: - Host modifier

extension View {
    /// Overlays the once-a-day blessing on top of this view the first
    /// time it appears on a new day, then dissolves to reveal it.
    /// Attach to the main experience so the app is already rendered
    /// behind the blessing when it fades away.
    func dailyBlessing() -> some View {
        modifier(DailyBlessingHost())
    }
}

private struct DailyBlessingHost: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var quote: DailyQuote?

    func body(content: Content) -> some View {
        ZStack {
            content

            if let quote {
                DailyBlessingView(quote: quote) {
                    self.quote = nil
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        // Cold launch into the main experience.
        .task { presentIfNeeded() }
        // Reopening a long-backgrounded app on a new day doesn't re-fire
        // `.task`, so re-check when the scene becomes active.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { presentIfNeeded() }
        }
    }

    private func presentIfNeeded() {
        guard quote == nil, DailyBlessing.shouldShow() else { return }
        DailyBlessing.markShown()
        // Fade the curtain in so it doesn't pop over the app.
        withAnimation(SacredMotion.respecting(SacredMotion.veil)) {
            quote = DailyBlessing.quote()
        }
    }
}
