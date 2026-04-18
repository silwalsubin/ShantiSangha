import SwiftUI

/// Full depth on a single planet — opens from a row tap on VedicChartView.
/// Carries the classical detail (divisional positions, dignity, status flags,
/// tradition interpretation) that would be too dense on the chart list itself.
struct PlanetDetailView: View {
    let planet: Planet

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                positionsSection
                let flags = statusRows
                if !flags.isEmpty {
                    statusSection(flags)
                }
                if let i = planet.interpretation {
                    traditionSection(i)
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle(planet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(planet.name)
                    .font(.sacredHeading)
                    .foregroundColor(.sacredText)
                if planet.retrograde == true {
                    Text("℞")
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundColor(.sacredGold.opacity(0.8))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(shortRashi(planet.rashi))
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredGold)
                Text(String(format: "%.2f°", planet.degree))
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }
            HStack(spacing: 6) {
                Text("\(planet.nakshatra) · Pada \(planet.pada)")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredTextSecondary)
                if let house = planet.house {
                    Text("·")
                        .font(.sacredMicro)
                        .foregroundColor(.sacredMuted)
                    Text("House \(house)")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredTextSecondary)
                }
            }
            if planet.dignity != "neutral" {
                Text(dignityLabel(planet.dignity))
                    .font(.sacredMicroBold)
                    .tracking(2)
                    .foregroundColor(dignityColor(planet.dignity))
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Positions (divisional charts)

    private var positionsSection: some View {
        card(title: "POSITIONS") {
            VStack(spacing: 0) {
                positionRow("Rasi (D1)", shortRashi(planet.rashi))
                Divider().padding(.vertical, 8)
                if let d9 = planet.navamsaRashi {
                    positionRow(
                        "Navamsa (D9)",
                        shortRashi(d9),
                        subtitle: planet.vargottama == true ? "vargottama — D1 and D9 match" : nil,
                        badge: planet.vargottama == true ? "★" : nil
                    )
                    Divider().padding(.vertical, 8)
                }
                if let d10 = planet.dasamsaRashi {
                    positionRow("Dasamsa (D10)", shortRashi(d10), subtitle: "career, public life")
                    Divider().padding(.vertical, 8)
                }
                if let d12 = planet.dvadasamsaRashi {
                    positionRow("Dvadasamsa (D12)", shortRashi(d12), subtitle: "parents, lineage")
                }
            }
        }
    }

    private func positionRow(_ label: String, _ value: String,
                             subtitle: String? = nil, badge: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .serif))
                .tracking(2)
                .foregroundColor(.sacredLabel)
                .frame(width: 130, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(value)
                        .font(.sacredTextMedium)
                        .foregroundColor(.sacredGold)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .bold, design: .serif))
                            .foregroundColor(.sacredGold)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.sacredMicro)
                        .italic()
                        .foregroundColor(.sacredMuted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Status

    private var statusRows: [(String, String)] {
        var rows: [(String, String)] = []
        if planet.retrograde == true { rows.append(("Retrograde", "moving backward along the ecliptic at birth")) }
        if planet.combust == true { rows.append(("Combust", "within the Sun's classical orb — natural strength muted")) }
        if planet.sandhi == true { rows.append(("Sandhi", "sits in the first or last 1° of its sign — cusp weakness")) }
        if planet.vargottama == true { rows.append(("Vargottama", "same sign in D1 and D9 — classically very strong")) }
        return rows
    }

    private func statusSection(_ rows: [(String, String)]) -> some View {
        card(title: "STATUS") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.0.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .serif))
                            .tracking(2)
                            .foregroundColor(.sacredGold)
                        Text(row.1)
                            .font(.sacredSmall)
                            .italic()
                            .foregroundColor(.sacredTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Tradition

    private func traditionSection(_ i: Interpretation) -> some View {
        card(title: "TRADITION SPEAKS") {
            VStack(alignment: .leading, spacing: 8) {
                Text(i.content)
                    .font(.sacredText)
                    .italic()
                    .foregroundColor(.sacredTextSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Text(i.source)
                    .font(.system(size: 9, weight: .regular, design: .serif))
                    .foregroundColor(.sacredMuted.opacity(0.7))
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Helpers

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredGold.opacity(0.08)))
    }

    private func shortRashi(_ rashi: String) -> String {
        rashi.components(separatedBy: " (").first ?? rashi
    }

    private func dignityColor(_ dignity: String) -> Color {
        switch dignity {
        case "deep_exalted", "exalted": return .sacredGreen
        case "moolatrikona", "own_sign": return .sacredGold
        case "debilitated": return .sacredRed
        default: return .sacredMuted
        }
    }

    private func dignityLabel(_ dignity: String) -> String {
        switch dignity {
        case "deep_exalted": return "DEEP EXALT"
        case "exalted": return "EXALTED"
        case "moolatrikona": return "MOOLATRIKONA"
        case "own_sign": return "OWN SIGN"
        case "debilitated": return "DEBILITATED"
        default: return ""
        }
    }
}
