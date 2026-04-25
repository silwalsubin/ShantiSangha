import SwiftUI

/// Renders the active gate inside the shared wizard chrome — page
/// background, step counter, progress dots, title + subtitle, sign-out
/// link in the footer. Each gate supplies only its body via `makeBody()`.
///
/// The step number reflects only the gates still unfinished in this pass.
/// Already-satisfied gates stay out of the chrome, so a returning user with
/// one missing field gets a quiet single-step flow instead of `STEP 3 OF 3`.
struct RequiredDataGateView: View {
    let gate: any RequiredGate
    let stepIndex: Int        // 0-based position among unfinished gates
    let totalSteps: Int       // total unfinished gates
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: SacredSpacing.l) {
                    Spacer().frame(height: SacredSpacing.xl)

                    if totalSteps > 1 {
                        wizardHeader
                    }

                    VStack(alignment: .leading, spacing: SacredSpacing.s) {
                        Text("WELCOME")
                            .font(.sacredSectionLabel)
                            .tracking(3)
                            .foregroundColor(.sacredLabel)

                        Text(gate.title)
                            .font(.sacredHeading)
                            .foregroundColor(.sacredText)

                        if let subtitle = gate.subtitle {
                            Text(subtitle)
                                .font(.sacredText)
                                .foregroundColor(.sacredTextSecondary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    gate.makeBody()

                    Spacer(minLength: SacredSpacing.l)

                    Button { auth.signOut() } label: {
                        Text("Sign out")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, SacredSpacing.m)
                }
                .padding(.horizontal, SacredSpacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        // Re-render the body with a soft fade when the active gate changes,
        // so advancing to the next step doesn't snap.
        .id(gate.id)
        .transition(.opacity)
    }

    // MARK: - Wizard header

    private var wizardHeader: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.s) {
            Text("STEP \(stepIndex + 1) OF \(totalSteps)")
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)

            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Circle()
                        .fill(dotColor(for: i))
                        .frame(width: 8, height: 8)
                }
            }
        }
    }

    private func dotColor(for index: Int) -> Color {
        if index < stepIndex {
            // Past steps — already satisfied; muted gold.
            return .sacredGold
        } else if index == stepIndex {
            // Current step — bright gold.
            return .sacredGold
        } else {
            // Future steps — empty.
            return .sacredMuted.opacity(0.25)
        }
    }
}
