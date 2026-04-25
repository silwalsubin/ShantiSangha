import SwiftUI

/// A card that displays the daily AI-generated reflection on the Home tab.
/// No title, no label by default — the card just speaks. When a `caption`
/// is provided (e.g. the user is seeing yesterday's reflection while today's
/// is still composing), a small uppercase label appears above the text.
/// When `onClose` is provided, a small dismiss affordance appears in the
/// top-right corner.
struct ReflectionCardView: View {
    let content: String
    var caption: String? = nil
    var onClose: (() -> Void)? = nil

    var body: some View {
        LuxCard {
            VStack(spacing: 14) {
                if let caption {
                    Text(caption)
                        .font(.system(size: 9, weight: .bold, design: .serif))
                        .tracking(2)
                        .foregroundColor(.sacredLabel)
                }
                Text(content)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .italic()
                    .foregroundColor(.sacredText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SacredSpacing.luxe)
            .padding(.vertical, SacredSpacing.luxe)
        }
        .overlay(alignment: .topTrailing) {
            if let onClose {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.sacredMuted.opacity(0.7))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss reflection")
            }
        }
        .padding(.horizontal, SacredSpacing.m)
    }
}
