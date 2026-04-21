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
        } else {
            unavailableCard
        }
    }

    private var loadingCard: some View {
        SacredCard("YOUR READING") {
            HStack(spacing: 10) {
                ProgressView().tint(.sacredGold)
                Text("Composing your reading from the classical sources…")
                    .font(.sacredMicro)
                    .italic()
                    .foregroundColor(.sacredMuted)
            }
        }
    }

    private var unavailableCard: some View {
        SacredCard("YOUR READING") {
            Text("Your reading will appear here once your chart is ready.")
                .font(.sacredMicro)
                .italic()
                .foregroundColor(.sacredMuted)
        }
    }

    private func loadedCard(_ reading: ChartReadingResponse) -> some View {
        SacredCard("YOUR READING") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ChartReadingSectionKey.ordered, id: \.key) { section in
                    if let prose = reading.sections[section.key], !prose.isEmpty {
                        row(key: section.key, title: section.title, prose: prose)
                    }
                }
            }
        }
    }

    private func row(key: String, title: String, prose: String) -> some View {
        SacredDisclosure(
            title,
            titleStyle: .body,
            isExpanded: disclosureBinding($expanded, key: key)
        ) {
            Text(prose)
                .font(.sacredSmall)
                .italic()
                .foregroundColor(.sacredTextSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
        }
    }
}
