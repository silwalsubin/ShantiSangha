import SwiftUI
import CoreLocation

/// Detailed Vedic birth chart — nakshatra attributes, lagna, 9 planets with
/// rashi/degree/house/nakshatra/pada, current dasha. Reached from Journey tab.
struct VedicChartView: View {
    @State private var chart: VedicChart?
    @State private var loading = true
    @State private var error: String?
    @State private var placeName: String?
    /// Tracks which interpretation panels are currently expanded, keyed by
    /// section id (e.g. "nakshatra", "lagna", "dasha", "planet.sun").
    @State private var expanded: Set<String> = []
    private let api = ApiService.shared

    var body: some View {
        ScrollView {
            if loading {
                ProgressView()
                    .tint(.sacredGold)
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if let error {
                errorView(error)
            } else if let chart, chart.available {
                VStack(alignment: .leading, spacing: 24) {
                    birthSummary(chart)
                    if let nakshatra = chart.nakshatra {
                        nakshatraSection(nakshatra)
                    }
                    if let lagna = chart.lagna {
                        lagnaSection(lagna)
                    }
                    if let dasha = chart.dasha {
                        dashaSection(dasha)
                    }
                    if let planets = chart.planets, !planets.isEmpty {
                        planetsSection(planets, hasHouses: chart.lagna != nil)
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            } else if let chart, !chart.available {
                unavailableView(reason: chart.reason)
            }
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .refreshable { await load() }
        .navigationTitle("Your Chart")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredGold)
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Sections

    private func birthSummary(_ chart: VedicChart) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BIRTH")
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)
            if let date = chart.birth?.date {
                Text(formatDate(date))
                    .font(.sacredTextMedium)
                    .foregroundColor(.sacredText)
            }
            if let time = chart.birth?.time {
                Text(formatTime(time))
                    .font(.sacredSmall)
                    .foregroundColor(.sacredTextSecondary)
            }
            if let place = placeName {
                HStack(spacing: 4) {
                    Image(systemName: "location")
                        .font(.sacredMicro)
                        .foregroundColor(.sacredGold.opacity(0.7))
                    Text(place)
                        .font(.sacredSmall)
                        .foregroundColor(.sacredTextSecondary)
                }
                .padding(.top, 2)
            }
            if chart.birth?.hasCoordinates == false {
                Text("Birth place is not set — add it in Settings to see your houses and ascendant.")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
                    .padding(.top, 6)
            }
        }
    }

    private func nakshatraSection(_ n: NakshatraAttrs) -> some View {
        card(title: "NAKSHATRA") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.name)
                        .font(.sacredHeading)
                        .foregroundColor(.sacredGold)
                    Text(n.quality)
                        .font(.sacredSmall)
                        .italic()
                        .foregroundColor(.sacredTextSecondary)
                }

                attributeGrid([
                    ("PADA", "\(n.pada) of 4"),
                    ("NADI", n.nadi),
                    ("GANA", n.gana),
                    ("YONI", n.yoni),
                    ("DEITY", n.deity),
                    ("LORD", n.lord)
                ])

                interpretationPanel(key: "nakshatra", interpretation: n.interpretation)
            }
        }
    }

    private func lagnaSection(_ l: Lagna) -> some View {
        card(title: "LAGNA (ASCENDANT)") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(l.rashi)
                        .font(.sacredSubheading)
                        .foregroundColor(.sacredGold)
                    Text(String(format: "%.2f°", l.degree))
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                }
                HStack(spacing: 6) {
                    Text(l.nakshatra)
                        .font(.sacredSmallMedium)
                        .foregroundColor(.sacredTextSecondary)
                    Text("·")
                        .font(.sacredMicro)
                        .foregroundColor(.sacredMuted)
                    Text("Pada \(l.pada)")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                }
                Text(l.nakshatraQuality)
                    .font(.sacredSmall)
                    .italic()
                    .foregroundColor(.sacredTextSecondary)
                    .padding(.top, 2)

                interpretationPanel(key: "lagna", interpretation: l.interpretation)
            }
        }
    }

    private func dashaSection(_ d: DashaInfo) -> some View {
        card(title: "CURRENT PERIOD") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(d.mahadasha)
                        .font(.sacredHeading)
                        .foregroundColor(.sacredGold)
                    Text("Mahadasha")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                }
                Text("\(formatDate(d.mahadashaStart)) → \(formatDate(d.mahadashaEnd))")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)

                Divider().padding(.vertical, 6)

                HStack(spacing: 8) {
                    Text(d.antardasha)
                        .font(.sacredSubheading)
                        .foregroundColor(.sacredText)
                    Text("Antardasha")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                }
                Text("\(formatDate(d.antardashaStart)) → \(formatDate(d.antardashaEnd))")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)

                interpretationPanel(key: "dasha", interpretation: d.interpretation)
            }
        }
    }

    private func planetsSection(_ planets: [Planet], hasHouses: Bool) -> some View {
        card(title: "PLANETS") {
            VStack(spacing: 0) {
                ForEach(Array(planets.enumerated()), id: \.element.name) { index, planet in
                    planetRow(planet, hasHouses: hasHouses)
                    if index < planets.count - 1 {
                        Divider().padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private func planetRow(_ p: Planet, hasHouses: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 3) {
                    Text(p.name)
                        .font(.sacredTextMedium)
                        .foregroundColor(.sacredText)
                    if p.retrograde == true {
                        Text("℞")
                            .font(.system(size: 11, weight: .regular, design: .serif))
                            .foregroundColor(.sacredGold.opacity(0.8))
                    }
                }
                .frame(width: 70, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(shortRashi(p.rashi))
                            .font(.sacredTextMedium)
                            .foregroundColor(.sacredGold)
                        Text(String(format: "%.2f°", p.degree))
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }
                    Text("\(p.nakshatra) · Pada \(p.pada)")
                        .font(.sacredMicro)
                        .foregroundColor(.sacredTextSecondary)
                    if let d9 = p.navamsaRashi {
                        HStack(spacing: 4) {
                            Text("D9 \(shortRashi(d9))")
                                .font(.sacredMicro)
                                .foregroundColor(.sacredMuted)
                            if p.vargottama == true {
                                Text("★")
                                    .font(.system(size: 8, weight: .bold, design: .serif))
                                    .foregroundColor(.sacredGold)
                            }
                        }
                    }
                    let flags = statusFlags(p)
                    if !flags.isEmpty {
                        Text(flags)
                            .font(.system(size: 8, weight: .regular, design: .serif))
                            .tracking(1)
                            .foregroundColor(.sacredMuted.opacity(0.8))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    if hasHouses, let house = p.house {
                        Text("H\(house)")
                            .font(.sacredSmallSemibold)
                            .foregroundColor(.sacredText)
                    }
                    if p.dignity != "neutral" {
                        Text(dignityLabel(p.dignity))
                            .font(.system(size: 8, weight: .bold, design: .serif))
                            .tracking(1.5)
                            .foregroundColor(dignityColor(p.dignity))
                    }
                }
            }

            interpretationPanel(key: "planet.\(p.name.lowercased())",
                                 interpretation: p.interpretation)
        }
    }

    /// Small lowercased status line — combust / sandhi / vargottama hint — for
    /// things we don't surface as the primary right-side badge. Kept muted and
    /// small so the row stays scannable.
    private func statusFlags(_ p: Planet) -> String {
        var parts: [String] = []
        if p.combust == true { parts.append("combust") }
        if p.sandhi == true { parts.append("sandhi") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Interpretation panel

    /// Expandable disclosure that reveals a tradition-sourced passage for the
    /// given chart element. Hidden entirely if the backend has no passage
    /// matching this element's signature.
    @ViewBuilder
    private func interpretationPanel(key: String, interpretation: Interpretation?) -> some View {
        if let interpretation {
            let isOpen = expanded.contains(key)
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        if isOpen { expanded.remove(key) } else { expanded.insert(key) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "book")
                            .font(.sacredMicro)
                            .foregroundColor(.sacredGold.opacity(0.7))
                        Text(isOpen ? "Hide tradition" : "Tradition speaks")
                            .font(.sacredMicro)
                            .tracking(1.5)
                            .foregroundColor(.sacredLabel)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold, design: .serif))
                            .foregroundColor(.sacredMuted)
                        Spacer()
                    }
                    .padding(.top, 8)
                }
                .buttonStyle(.plain)

                if isOpen {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(interpretation.content)
                            .font(.sacredSmall)
                            .italic()
                            .foregroundColor(.sacredTextSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(interpretation.source)
                            .font(.system(size: 9, weight: .regular, design: .serif))
                            .foregroundColor(.sacredMuted.opacity(0.7))
                            .padding(.top, 2)
                    }
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: - Helpers

    private func attributeGrid(_ items: [(String, String)]) -> some View {
        let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.0)
                        .font(.system(size: 8, weight: .bold, design: .serif))
                        .tracking(1.5)
                        .foregroundColor(.sacredLabel)
                    Text(item.1)
                        .font(.sacredSmallMedium)
                        .foregroundColor(.sacredText)
                }
            }
        }
    }

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

    private func dignityColor(_ dignity: String) -> Color {
        switch dignity {
        case "deep_exalted": return .sacredGreen
        case "exalted": return .sacredGreen
        case "moolatrikona": return .sacredGold
        case "own_sign": return .sacredGold
        case "debilitated": return .sacredRed
        default: return .sacredMuted
        }
    }

    /// Map machine-readable dignity values to the UI label shown on the row.
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

    /// Strips the English name in parens — e.g. "Mithuna (Gemini)" → "Mithuna"
    private func shortRashi(_ rashi: String) -> String {
        rashi.components(separatedBy: " (").first ?? rashi
    }

    private func formatDate(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso.prefix(10).description) else { return iso }
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }

    private func formatTime(_ time: String) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        guard let d = f.date(from: String(time.prefix(5))) else { return time }
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.sacredHeading)
                .foregroundColor(.sacredRed)
            Text(message)
                .font(.sacredSmall)
                .foregroundColor(.sacredTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(16)
    }

    private func unavailableView(reason: String?) -> some View {
        VStack(spacing: 12) {
            Text("Your birth details are incomplete.")
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)
                .multilineTextAlignment(.center)
            Text(reasonMessage(reason))
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(16)
    }

    private func reasonMessage(_ reason: String?) -> String {
        switch reason {
        case "missing_birth_date_or_time":
            return "Add your birth date and time in Settings to see your full chart."
        case "invalid_birth_time":
            return "Your birth time couldn't be parsed. Try re-entering it in Settings."
        default:
            return "Complete your birth details in Settings to unlock your chart."
        }
    }

    // MARK: - Network

    private func load() async {
        loading = true
        error = nil
        do {
            let result: VedicChart = try await api.get("/jyotish/chart")
            chart = result
            await reverseGeocodeBirthPlace(result.birth?.place)
        } catch {
            if !error.isCancellation {
                self.error = "Couldn't load your chart. \(error.localizedDescription)"
            }
        }
        loading = false
    }

    /// BirthPlace is stored as "lat,lon" — reverse-geocode to a human name
    /// for display on the chart view.
    private func reverseGeocodeBirthPlace(_ place: String?) async {
        guard let place else { return }
        let parts = place.split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let lon = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { return }

        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: lat, longitude: lon))
            if let pm = placemarks.first {
                let parts = [pm.locality, pm.administrativeArea, pm.country]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                placeName = parts.joined(separator: ", ")
            }
        } catch {
            // Non-fatal — just don't show a name.
        }
    }
}

// MARK: - Response models

struct VedicChart: Decodable {
    let available: Bool
    let reason: String?
    let birth: Birth?
    let nakshatra: NakshatraAttrs?
    let lagna: Lagna?
    let planets: [Planet]?
    let dasha: DashaInfo?

    struct Birth: Decodable {
        let date: String
        let time: String?
        let place: String?
        let hasCoordinates: Bool
    }
}

struct Interpretation: Decodable {
    let content: String
    let source: String
    let polarity: String
    let themes: [String]
}

struct NakshatraAttrs: Decodable {
    let name: String
    let quality: String
    let pada: Int
    let yoni: String
    let nadi: String
    let gana: String
    let deity: String
    let lord: String
    let interpretation: Interpretation?
}

struct Lagna: Decodable {
    let rashi: String
    let degree: Double
    let nakshatra: String
    let nakshatraQuality: String
    let pada: Int
    let interpretation: Interpretation?
}

struct Planet: Decodable {
    let name: String
    let rashi: String
    let degree: Double
    let nakshatra: String
    let nakshatraQuality: String
    let pada: Int
    let house: Int?
    /// deep_exalted | exalted | moolatrikona | own_sign | debilitated | neutral
    let dignity: String
    /// Navamsa (D9) sign — "Simha (Leo)" format
    let navamsaRashi: String?
    /// True when the planet's D1 sign == D9 sign — classically very strong
    let vargottama: Bool?
    let retrograde: Bool?
    let combust: Bool?
    let sandhi: Bool?
    let interpretation: Interpretation?
}

struct DashaInfo: Decodable {
    let mahadasha: String
    let antardasha: String
    let antardashaStart: String
    let antardashaEnd: String
    let mahadashaStart: String
    let mahadashaEnd: String
    let interpretation: Interpretation?
}
