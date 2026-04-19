import SwiftUI

/// "Your Reading" card on the Birth Chart page. Six collapsible sections
/// composed server-side from the user's chart + classical Brihat Jataka
/// passages. Extracted from VedicChartView so the main file stays small
/// enough for the SwiftUI type checker to infer quickly.
struct ChartReadingCard: View {
    let reading: ChartReadingResponse?
    let loading: Bool
    @State private var expanded: Set<String> = []

    var body: some View {
        if loading && reading == nil {
            loadingCard
        } else if let reading, !reading.sections.isEmpty {
            loadedCard(reading)
        }
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR READING")
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)
            HStack(spacing: 10) {
                ProgressView().tint(.sacredGold)
                Text("Composing your reading from the classical sources…")
                    .font(.sacredMicro)
                    .italic()
                    .foregroundColor(.sacredMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredGold.opacity(0.08)))
    }

    private func loadedCard(_ reading: ChartReadingResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YOUR READING")
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(ChartReadingSectionKey.ordered, id: \.key) { section in
                    if let prose = reading.sections[section.key], !prose.isEmpty {
                        row(key: section.key, title: section.title, prose: prose)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredGold.opacity(0.08)))
    }

    private func row(key: String, title: String, prose: String) -> some View {
        let isOpen = expanded.contains(key)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if isOpen { expanded.remove(key) } else { expanded.insert(key) }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.sacredText)
                    Spacer(minLength: 0)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold, design: .serif))
                        .foregroundColor(.sacredMuted.opacity(0.6))
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Text(prose)
                    .font(.sacredSmall)
                    .italic()
                    .foregroundColor(.sacredTextSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
