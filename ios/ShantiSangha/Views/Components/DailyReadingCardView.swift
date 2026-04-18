import SwiftUI

/// A short Vedic daily reading that appears as a sealed note on Home.
/// The user taps to open it — the reading is always present, but they
/// choose whether to engage with it today.
struct DailyReadingCardView: View {
    let content: String
    @Binding var isOpened: Bool

    var body: some View {
        Group {
            if isOpened {
                openedView
            } else {
                sealedView
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Sealed

    private var sealedView: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                isOpened = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "envelope")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredGold)

                Text("today's reading")
                    .font(.sacredSmall)
                    .italic()
                    .foregroundColor(.sacredTextSecondary)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.sacredGold.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.sacredGold.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .transition(.scale(scale: 0.97).combined(with: .opacity))
    }

    // MARK: - Opened

    private var openedView: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "envelope.open")
                .font(.sacredMicro)
                .foregroundColor(.sacredGold.opacity(0.6))
                .padding(.top, 3)

            Text(content)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .italic()
                .foregroundColor(.sacredTextSecondary)
                .multilineTextAlignment(.leading)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.sacredGold.opacity(0.12), lineWidth: 0.5)
                )
        )
        .transition(.scale(scale: 0.97).combined(with: .opacity))
    }
}
