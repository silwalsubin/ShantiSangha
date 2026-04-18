import SwiftUI
import CoreLocation
import PhosphorSwift

/// Detailed Vedic birth chart — nakshatra attributes, lagna, 9 planets with
/// rashi/degree/house/nakshatra/pada, current dasha. Reached from Journey tab.
struct VedicChartView: View {
    @State private var chart: VedicChart?
    @State private var loading = true
    @State private var error: String?
    /// Tracks which interpretation panels are currently expanded, keyed by
    /// section id (e.g. "nakshatra", "lagna", "dasha", "planet.sun").
    @State private var expanded: Set<String> = []

    // Birth details — editable from this page; single source of truth for the chart.
    @State private var birthDate: Date?
    @State private var birthTime: Date?
    @State private var birthPlace: String = ""
    @State private var birthPlaceQuery: String = ""
    @State private var birthDetailsLoaded = false
    @State private var showBirthDatePicker = false
    @State private var showBirthTimePicker = false
    @State private var showBirthPlacePicker = false

    private let api = ApiService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                birthDetailsCard

                if loading {
                    ProgressView()
                        .tint(.sacredGold)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let error {
                    errorView(error)
                } else if let chart, chart.available {
                    if let planets = chart.planets, !planets.isEmpty {
                        rashiSection(planets: planets)
                    }
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
                        legendSection()
                    }
                } else if let chart, !chart.available {
                    unavailablePrompt(reason: chart.reason)
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .refreshable { await load() }
        .navigationTitle("Your Birth Chart")
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
        .task { await loadBirthDetails() }
        .task { await load() }
        .sheet(isPresented: $showBirthDatePicker) { birthDateSheet }
        .sheet(isPresented: $showBirthTimePicker) { birthTimeSheet }
        .sheet(isPresented: $showBirthPlacePicker) {
            BirthPlacePickerView(
                selectedPlace: birthPlaceQuery,
                onSelect: { name, lat, lng in
                    birthPlaceQuery = name
                    birthPlace = "\(String(format: "%.4f", lat)),\(String(format: "%.4f", lng))"
                    showBirthPlacePicker = false
                    Task { await saveBirthDetails(); await load() }
                }
            )
        }
    }

    // MARK: - Birth details (editable)

    private var birthDetailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BIRTH")
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)

            birthRow(
                icon: Ph.calendar.duotone,
                label: birthDate.map { formatBirthDate($0) } ?? "Add birth date",
                set: birthDate != nil
            ) { showBirthDatePicker = true }

            Divider()

            birthRow(
                icon: Ph.clock.duotone,
                label: birthTime.map { formatBirthTime($0) } ?? "Add birth time",
                set: birthTime != nil
            ) { showBirthTimePicker = true }

            Divider()

            birthRow(
                icon: Ph.mapPin.duotone,
                label: birthPlaceQuery.isEmpty ? "Add birth place" : birthPlaceQuery,
                set: !birthPlaceQuery.isEmpty
            ) { showBirthPlacePicker = true }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredGold.opacity(0.08)))
    }

    private func birthRow(icon: Image, label: String, set: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.sacredGold.opacity(0.75))
                    .frame(width: 22, alignment: .center)
                Text(label)
                    .font(.sacredText)
                    .foregroundColor(set ? .sacredText : .sacredMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.sacredMuted.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var birthDateSheet: some View {
        NavigationStack {
            DatePicker(
                "Date of birth",
                selection: Binding(
                    get: { birthDate ?? Calendar.current.date(byAdding: .year, value: -25, to: Date())! },
                    set: { birthDate = $0 }
                ),
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding()
            .background(Color.sacredBg.ignoresSafeArea())
            .navigationTitle("Date of birth")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if birthDate == nil {
                    birthDate = Calendar.current.date(byAdding: .year, value: -25, to: Date())
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showBirthDatePicker = false
                        Task { await saveBirthDetails(); await load() }
                    }
                    .foregroundColor(.sacredGold)
                }
            }
        }
        .presentationDetents([.height(300)])
    }

    private var birthTimeSheet: some View {
        NavigationStack {
            DatePicker(
                "Time of birth",
                selection: Binding(
                    get: { birthTime ?? Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date())! },
                    set: { birthTime = $0 }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding()
            .background(Color.sacredBg.ignoresSafeArea())
            .navigationTitle("Time of birth")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if birthTime == nil {
                    birthTime = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date())
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showBirthTimePicker = false
                        Task { await saveBirthDetails(); await load() }
                    }
                    .foregroundColor(.sacredGold)
                }
            }
        }
        .presentationDetents([.height(300)])
    }

    // MARK: - Sections

    /// Rashi = Chandra Rashi = the Moon's sign at birth. Primary Jyotish
    /// identifier — what people mean when they say "my rashi".
    private func rashiSection(planets: [Planet]) -> some View {
        guard let moon = planets.first(where: { $0.name == "Moon" }) else {
            return AnyView(EmptyView())
        }
        return AnyView(
            card(title: "RASHI") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(shortRashi(moon.rashi))
                        .font(.sacredHeading)
                        .foregroundColor(.sacredGold)
                    Text("moon sign · chandra rashi")
                        .font(.sacredSmall)
                        .italic()
                        .foregroundColor(.sacredMuted)
                }
            }
        )
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
            if hasHouses {
                groupedByHouse(planets)
            } else {
                ungroupedPlanets(planets)
            }
        }
    }

    /// House-grouped view. Only occupied houses appear — empty houses matter
    /// in Jyotish but belong in a deeper view; here we keep the chart dense
    /// and let the structure of the chart show through the groupings.
    private func groupedByHouse(_ planets: [Planet]) -> some View {
        let grouped = Dictionary(grouping: planets.compactMap { p -> (Int, Planet)? in
            guard let h = p.house else { return nil }
            return (h, p)
        }, by: { $0.0 })
        let occupied = grouped.keys.sorted()

        return VStack(alignment: .leading, spacing: 18) {
            ForEach(occupied, id: \.self) { house in
                let housePlanets = grouped[house]!.map { $0.1 }
                houseGroup(house: house, planets: housePlanets)
            }
        }
    }

    private func houseGroup(house: Int, planets: [Planet]) -> some View {
        // In whole-sign houses every planet in a house shares that house's sign.
        let sign = planets.first?.rashi ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("HOUSE \(house)")
                    .font(.sacredSectionLabel)
                    .tracking(2)
                    .foregroundColor(.sacredLabel)
                Text("·")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
                Text(shortRashi(sign).uppercased())
                    .font(.sacredSectionLabel)
                    .tracking(2)
                    .foregroundColor(.sacredGold)
                if house == 1 {
                    Text("·")
                        .font(.sacredMicro)
                        .foregroundColor(.sacredMuted)
                    Text("LAGNA")
                        .font(.sacredSectionLabel)
                        .tracking(2)
                        .foregroundColor(.sacredGold.opacity(0.7))
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(planets.enumerated()), id: \.element.name) { idx, planet in
                    NavigationLink(destination: PlanetDetailView(planet: planet)) {
                        housePlanetRow(planet)
                    }
                    .buttonStyle(.plain)
                    if idx < planets.count - 1 {
                        Divider().padding(.vertical, 8)
                    }
                }
            }
        }
    }

    /// Planet row inside a house group. Sign is omitted (carried by the
    /// header) — each row just carries what's unique to the planet.
    private func housePlanetRow(_ p: Planet) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(p.name)
                .font(.sacredTextMedium)
                .foregroundColor(.sacredText)
                .frame(width: 80, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: "%.2f°", p.degree))
                    .font(.sacredTextMedium)
                    .foregroundColor(.sacredGold)
                Text("\(p.nakshatra) · Pada \(p.pada)")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredTextSecondary)
            }

            Spacer()

            stateIcons(p)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .regular, design: .serif))
                .foregroundColor(.sacredMuted.opacity(0.5))
                .padding(.leading, 4)
        }
        .contentShape(Rectangle())
    }

    /// Fallback for charts without an ascendant (no lat/lon): plain list,
    /// no house grouping since we have nothing to group on.
    private func ungroupedPlanets(_ planets: [Planet]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(planets.enumerated()), id: \.element.name) { index, planet in
                NavigationLink(destination: PlanetDetailView(planet: planet)) {
                    ungroupedPlanetRow(planet)
                }
                .buttonStyle(.plain)
                if index < planets.count - 1 {
                    Divider().padding(.vertical, 10)
                }
            }
        }
    }

    private func ungroupedPlanetRow(_ p: Planet) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(p.name)
                .font(.sacredTextMedium)
                .foregroundColor(.sacredText)
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
            }

            Spacer()

            stateIcons(p)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .regular, design: .serif))
                .foregroundColor(.sacredMuted.opacity(0.5))
                .padding(.leading, 4)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Legend

    /// Explains every icon used in the planet rows. Language is written for
    /// someone new to Vedic astrology — skip the jargon, focus on what each
    /// state means for how the planet shows up in the person's life.
    private func legendSection() -> some View {
        card(title: "LEGEND") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Each mark describes how a planet is showing up in this chart — whether it's strong, at home, or facing a quiet challenge.")
                    .font(.sacredSmall)
                    .italic()
                    .foregroundColor(.sacredTextSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                legendGroup(
                    title: "Positive",
                    rows: [
                        (Ph.arrowCircleUp.fill, .sacredGreen, "Deep Exalted",
                         "At the very peak of its strength — a rare placement where the planet's best qualities shine most clearly."),
                        (Ph.arrowCircleUp.duotone, .sacredGreen.opacity(0.85), "Exalted",
                         "In the sign that amplifies its natural qualities. The planet expresses itself with confidence and ease."),
                        (Ph.crownSimple.duotone, .sacredGreen.opacity(0.7), "Moolatrikona",
                         "In its honored seat — acts with authority and purpose, deeply connected to its role in the chart."),
                        (Ph.anchor.duotone, .sacredGreen.opacity(0.55), "Own Sign",
                         "The planet is at home. It expresses itself freely and without effort here."),
                        (Ph.squaresFour.duotone, .sacredGreen.opacity(0.9), "Vargottama",
                         "The planet occupies the same sign in two key charts — a sign of consistent, reinforced strength.")
                    ]
                )
                legendGroup(
                    title: "Challenging",
                    rows: [
                        (Ph.arrowCircleDown.duotone, .sacredRed, "Debilitated",
                         "In a sign where it feels out of place. Not a fault — a quiet invitation to grow into this part of life."),
                        (Ph.sunDim.duotone, .sacredRed.opacity(0.75), "Combust",
                         "Sitting too close to the Sun. Its outward expression is quieter; its energy turns inward rather than broadcasting."),
                        (Ph.circleHalf.duotone, .sacredRed.opacity(0.55), "Sandhi",
                         "Right at a sign boundary — between two worlds. Its character feels less settled, as if it's in transition.")
                    ]
                )
                legendGroup(
                    title: "Notable",
                    rows: [
                        (Ph.arrowUUpLeft.duotone, .sacredGold.opacity(0.75), "Retrograde",
                         "Moving backward through the zodiac at birth. Classically a sign of intensified strength — its themes come through with extra depth.")
                    ]
                )
            }
        }
    }

    private func legendGroup(title: String,
                             rows: [(Image, Color, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .serif))
                .tracking(2)
                .foregroundColor(.sacredLabel)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 10) {
                        row.0
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                            .foregroundColor(row.1)
                            .frame(width: 20, alignment: .center)
                            .padding(.top, 1)
                        Text(row.2)
                            .font(.sacredSmallSemibold)
                            .foregroundColor(.sacredText)
                            .frame(width: 110, alignment: .leading)
                        Text(row.3)
                            .font(.sacredMicro)
                            .italic()
                            .foregroundColor(.sacredTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
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

    /// Colors are tiered by classical strength. Opacity runs from 1.0
    /// (strongest/rarest) down to 0.55 (most common/subtle) so a user scanning
    /// the chart can weigh each mark's importance at a glance.
    private func dignityColor(_ dignity: String) -> Color {
        switch dignity {
        case "deep_exalted": return .sacredGreen
        case "exalted": return .sacredGreen.opacity(0.85)
        case "moolatrikona": return .sacredGreen.opacity(0.7)
        case "own_sign": return .sacredGreen.opacity(0.55)
        case "debilitated": return .sacredRed
        default: return .sacredMuted
        }
    }

    /// Phosphor icon for each dignity state, matching the legend.
    private func dignityIcon(_ dignity: String) -> Image? {
        switch dignity {
        case "deep_exalted": return Ph.arrowCircleUp.fill
        case "exalted": return Ph.arrowCircleUp.duotone
        case "moolatrikona": return Ph.crownSimple.duotone
        case "own_sign": return Ph.anchor.duotone
        case "debilitated": return Ph.arrowCircleDown.duotone
        default: return nil
        }
    }

    /// Horizontal stack of state indicators for a chart row. Positives first
    /// (dignity, vargottama), challenges after (combust, sandhi). Retrograde
    /// is shown separately next to the planet name. Full explanations live on
    /// PlanetDetailView — icons here just signal "there's something to see."
    @ViewBuilder
    private func stateIcons(_ p: Planet) -> some View {
        HStack(spacing: 8) {
            if let icon = dignityIcon(p.dignity) {
                stateGlyph(icon, color: dignityColor(p.dignity), label: dignityLabel(p.dignity))
            }
            if p.vargottama == true {
                stateGlyph(Ph.squaresFour.duotone, color: .sacredGreen.opacity(0.9), label: "Vargottama")
            }
            if p.retrograde == true {
                stateGlyph(Ph.arrowUUpLeft.duotone, color: .sacredGold.opacity(0.75), label: "Retrograde")
            }
            if p.combust == true {
                stateGlyph(Ph.sunDim.duotone, color: .sacredRed.opacity(0.75), label: "Combust")
            }
            if p.sandhi == true {
                stateGlyph(Ph.circleHalf.duotone, color: .sacredRed.opacity(0.55), label: "Sandhi")
            }
        }
    }

    private func stateGlyph(_ image: Image, color: Color, label: String) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 15, height: 15)
            .foregroundColor(color)
            .accessibilityLabel(label)
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

    private func unavailablePrompt(reason: String?) -> some View {
        VStack(spacing: 10) {
            Text(reasonMessage(reason))
                .font(.sacredSmall)
                .italic()
                .foregroundColor(.sacredMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private func reasonMessage(_ reason: String?) -> String {
        switch reason {
        case "missing_birth_date_or_time":
            return "Add your birth date and time above to see your full chart."
        case "invalid_birth_time":
            return "Your birth time couldn't be parsed. Try re-entering it above."
        default:
            return "Complete your birth details above to unlock your chart."
        }
    }

    // MARK: - Network

    private func load() async {
        loading = true
        error = nil
        do {
            let result: VedicChart = try await api.get("/jyotish/chart")
            chart = result
        } catch {
            if !error.isCancellation {
                self.error = "Couldn't load your chart. \(error.localizedDescription)"
            }
        }
        loading = false
    }

    // MARK: - Birth details I/O

    private func loadBirthDetails() async {
        guard !birthDetailsLoaded else { return }
        do {
            let response: MeResponse = try await api.get("/me")
            if let profile = response.profile {
                if let dateStr = profile.birthDate {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd"
                    birthDate = df.date(from: dateStr)
                }
                if let timeStr = profile.birthTime {
                    let df = DateFormatter()
                    df.dateFormat = "HH:mm"
                    birthTime = df.date(from: timeStr)
                }
                if let place = profile.birthPlace, !place.isEmpty {
                    birthPlace = place
                    let parts = place.split(separator: ",")
                    if parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]) {
                        let location = CLLocation(latitude: lat, longitude: lng)
                        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
                            birthPlaceQuery = [placemark.locality, placemark.country]
                                .compactMap { $0 }
                                .joined(separator: ", ")
                        }
                    }
                }
            }
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Chart", "Failed to load birth details: \(error)")
            }
        }
        birthDetailsLoaded = true
    }

    private func saveBirthDetails() async {
        var body: [String: Any] = [:]
        if let date = birthDate {
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            body["birthDate"] = df.string(from: date)
        }
        if let time = birthTime {
            let df = DateFormatter(); df.dateFormat = "HH:mm"
            body["birthTime"] = df.string(from: time)
        }
        if !birthPlace.isEmpty {
            body["birthPlace"] = birthPlace
        }
        guard !body.isEmpty, let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        do {
            let _: EmptyResponse = try await api.patchRaw("/me", body: data)
            AppLogger.shared.info("Chart", "Birth details saved: \(body.keys.joined(separator: ", "))")
        } catch {
            AppLogger.shared.error("Chart", "Birth save failed: \(error)")
        }
    }

    // MARK: - Formatting

    private func formatBirthDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    private func formatBirthTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

private struct MeResponse: Decodable {
    let profile: MeProfileData?
}

private struct MeProfileData: Decodable {
    let birthDate: String?
    let birthTime: String?
    let birthPlace: String?
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

struct Planet: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let rashi: String
    let degree: Double
    let nakshatra: String
    let nakshatraQuality: String
    let pada: Int
    let house: Int?
    /// deep_exalted | exalted | moolatrikona | own_sign | debilitated | neutral
    let dignity: String
    let drekkanaRashi: String?
    let chaturthamsaRashi: String?
    let saptamsaRashi: String?
    let navamsaRashi: String?
    let dasamsaRashi: String?
    let dvadasamsaRashi: String?
    let shodasamsaRashi: String?
    let vimsamsaRashi: String?
    let chaturvimsamsaRashi: String?
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
