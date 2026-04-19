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
            let badges = stateBadges
            if !badges.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                        HStack(alignment: .top, spacing: 10) {
                            badge.icon
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                                .foregroundColor(badge.color)
                                .frame(width: 22, alignment: .center)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(badge.label)
                                    .font(.sacredMicroBold)
                                    .tracking(2)
                                    .foregroundColor(badge.color)
                                Text(badge.description)
                                    .font(.sacredMicro)
                                    .italic()
                                    .foregroundColor(.sacredTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    /// Badges shown at the top of the detail page, in classical priority
    /// order: dignity (primary state) → vargottama (strength reinforcement)
    /// → combust (energy muted) → sandhi (cusp weakness). Mirrors the legend
    /// on the chart view so colors and icons stay consistent.
    private var stateBadges: [(icon: Image, color: Color, label: String, description: String)] {
        var badges: [(icon: Image, color: Color, label: String, description: String)] = []
        if planet.dignity != "neutral", let icon = dignityIcon(planet.dignity) {
            badges.append((icon, dignityColor(planet.dignity), dignityLabel(planet.dignity), dignityDescription(planet.dignity)))
        }
        if planet.vargottama == true {
            badges.append((Image(systemName: "square.grid.2x2"), .sacredGreen, "VARGOTTAMA",
                           "same sign in D1 and D9 — classically very strong"))
        }
        if planet.retrograde == true {
            badges.append((Image(systemName: "arrow.uturn.left"), .sacredGold, "RETROGRADE",
                           "moving backward along the ecliptic at birth"))
        }
        if planet.combust == true {
            badges.append((Image(systemName: "sun.haze"), .sacredRed, "COMBUST",
                           "within the Sun's classical orb — natural strength muted"))
        }
        if planet.sandhi == true {
            badges.append((Image(systemName: "circle.righthalf.filled"), .sacredRed, "SANDHI",
                           "sits in the first or last 1° of its sign — cusp weakness"))
        }
        return badges
    }

    // MARK: - Positions (divisional charts)

    private var positionsSection: some View {
        card(title: "POSITIONS") {
            VStack(spacing: 0) {
                positionRow("Rasi (D1)", shortRashi(planet.rashi), subtitle: "physical self, overall life")
                Divider().padding(.vertical, 8)
                if let d3 = planet.drekkanaRashi {
                    positionRow("Drekkana (D3)", shortRashi(d3), subtitle: "siblings, courage")
                    Divider().padding(.vertical, 8)
                }
                if let d4 = planet.chaturthamsaRashi {
                    positionRow("Chaturthamsa (D4)", shortRashi(d4), subtitle: "home, property, inner life")
                    Divider().padding(.vertical, 8)
                }
                if let d7 = planet.saptamsaRashi {
                    positionRow("Saptamsa (D7)", shortRashi(d7), subtitle: "children, creativity")
                    Divider().padding(.vertical, 8)
                }
                if let d9 = planet.navamsaRashi {
                    positionRow(
                        "Navamsa (D9)",
                        shortRashi(d9),
                        subtitle: planet.vargottama == true
                            ? "vargottama — D1 and D9 match"
                            : "marriage, dharma, planetary strength",
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
                    Divider().padding(.vertical, 8)
                }
                if let d16 = planet.shodasamsaRashi {
                    positionRow("Shodasamsa (D16)", shortRashi(d16), subtitle: "vehicles, comforts")
                    Divider().padding(.vertical, 8)
                }
                if let d20 = planet.vimsamsaRashi {
                    positionRow("Vimsamsa (D20)", shortRashi(d20), subtitle: "spiritual practice, upasana")
                    Divider().padding(.vertical, 8)
                }
                if let d24 = planet.chaturvimsamsaRashi {
                    positionRow("Chaturvimsamsa (D24)", shortRashi(d24), subtitle: "learning, education")
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
        case "deep_exalted", "exalted", "moolatrikona", "own_sign": return .sacredGreen
        case "debilitated": return .sacredRed
        default: return .sacredMuted
        }
    }

    private func dignityIcon(_ dignity: String) -> Image? {
        switch dignity {
        case "deep_exalted": return Image(systemName: "arrow.up.circle.fill")
        case "exalted": return Image(systemName: "arrow.up.circle")
        case "moolatrikona": return Image(systemName: "crown")
        case "own_sign": return Image(systemName: "house")
        case "debilitated": return Image(systemName: "arrow.down.circle")
        default: return nil
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

    private func dignityDescription(_ dignity: String) -> String {
        switch dignity {
        case "deep_exalted": return "at the classical peak degree of exaltation — maximum strength"
        case "exalted": return "in its sign of exaltation — natural strength elevated"
        case "moolatrikona": return "in its moolatrikona sign — strong, dignified placement"
        case "own_sign": return "in its own sign — comfortable and steady"
        case "debilitated": return "in its sign of debilitation — natural strength weakened"
        default: return ""
        }
    }
}
