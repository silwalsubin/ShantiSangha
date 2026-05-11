import SwiftUI

/// Shared "what + why" pill. The visible label is the *what* (e.g.
/// "2/8+ sectors", "Rule violation", "Over 10% cap"); tapping reveals
/// the *why* in a compact sacred-styled popover.
///
/// Two convenience inits:
///   - `init(label:tint:explanation:)` — plain-text explanation.
///   - `init(label:tint:detail:)`      — custom view builder for rich
///     popover content (e.g. explanation paragraph + chips below).
///
/// Visible footprint matches the existing capsule style used across
/// the app (caption-weight type, 12% tint background). Popover sticks
/// to compact adaptation on iPhone so it never feels like a sheet.
struct SacredStatusBadge<Detail: View>: View {
    let label: String
    let tint: Color
    @ViewBuilder let detail: () -> Detail

    @State private var showDetail = false

    init(label: String,
         tint: Color = .sacredMuted,
         @ViewBuilder detail: @escaping () -> Detail)
    {
        self.label = label
        self.tint = tint
        self.detail = detail
    }

    var body: some View {
        Button {
            showDetail = true
        } label: {
            Text(label)
                .font(.sacredSmallSemibold)
                .foregroundColor(tint)
                .padding(.horizontal, SacredSpacing.s)
                .padding(.vertical, SacredSpacing.xxs)
                .background(Capsule().fill(tint.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDetail) {
            VStack(alignment: .leading, spacing: SacredSpacing.s) {
                Text(label)
                    .font(.sacredSectionLabel)
                    .foregroundColor(tint)
                detail()
            }
            .padding(SacredSpacing.m)
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
            .background(Color.sacredBgCard)
            .presentationCompactAdaptation(.popover)
        }
    }
}

// Convenience for the common "just a paragraph" case.
extension SacredStatusBadge where Detail == SacredStatusBadgeText {
    init(label: String, tint: Color = .sacredMuted, explanation: String) {
        self.init(label: label, tint: tint) {
            SacredStatusBadgeText(text: explanation)
        }
    }
}

struct SacredStatusBadgeText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.sacredText)
            .foregroundColor(.sacredText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
