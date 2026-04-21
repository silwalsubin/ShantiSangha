import SwiftUI
import CoreLocation

/// Detailed Vedic birth chart — nakshatra attributes, lagna, 9 planets with
/// rashi/degree/house/nakshatra/pada, current dasha. Reached from Home's
/// daily reading card ("Read your full chart") and from the profile menu.
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
    @State private var pendingChatId: String?
    @State private var startingChat = false

    // Draft values for the date/time sheets — only commit to birthDate/birthTime
    // on Done. Prevents the "peek and dismiss" flow from writing a default.
    @State private var draftBirthDate: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var draftBirthTime: Date = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date()) ?? Date()

    // Inline banner for save/load errors. Warm message, no raw details.
    @State private var toastMessage: String?

    // Pre-composed chart reading (classical corpus-grounded). Loaded in
    // parallel with the chart; generation on first access can take ~10s.
    @State private var reading: ChartReadingResponse?
    @State private var readingLoading = false

    private let api = ApiService.shared

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    birthDetailsCard

                    if loading && chart == nil {
                        ProgressView()
                            .tint(.sacredGold)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let error, chart == nil {
                        errorView(error)
                    } else if let chart, chart.available {
                        ChartReadingCard(reading: reading, loading: readingLoading)

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
                        }
                    } else if let chart, !chart.available {
                        unavailablePrompt(reason: chart.reason)
                    }
                }
                .padding(16)
                .padding(.bottom, 100)
            }
            .background(Color.sacredBg.ignoresSafeArea())
            .refreshable { await refreshAll(force: true) }
            .sacredToast($toastMessage)

            askChartFAB
        }
        .navigationTitle("Your Birth Chart")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await refreshAll(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredGold)
                }
            }
        }
        .task { await refreshAll(force: false) }
        .sheet(isPresented: $showBirthDatePicker) { birthDateSheet }
        .sheet(isPresented: $showBirthTimePicker) { birthTimeSheet }
        .onChange(of: showBirthDatePicker) { _, presented in
            if presented {
                // Seed draft from the real value; if unset, default to 25y ago.
                draftBirthDate = birthDate
                    ?? Calendar.current.date(byAdding: .year, value: -25, to: Date())
                    ?? Date()
            }
        }
        .onChange(of: showBirthTimePicker) { _, presented in
            if presented {
                draftBirthTime = birthTime
                    ?? Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date())
                    ?? Date()
            }
        }
        .sheet(isPresented: $showBirthPlacePicker) {
            BirthPlacePickerView(
                selectedPlace: birthPlaceQuery,
                onSelect: { name, lat, lng in
                    birthPlaceQuery = name
                    let coords = "\(String(format: "%.4f", lat)),\(String(format: "%.4f", lng))"
                    birthPlace = coords
                    cachePlaceName(coords: coords, name: name)
                    showBirthPlacePicker = false
                    Task { await saveBirthDetails(); await load() }
                }
            )
        }
        .navigationDestination(item: $pendingChatId) { id in
            ChatView(conversationId: id, title: "Chart — \(chatTitleDate())")
        }
    }

    // MARK: - Ask-the-chart FAB

    private var askChartFAB: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await startChartChat() }
        } label: {
            Group {
                if startingChat {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "bubble.left")
                        .font(.sacredHeading)
                        .foregroundColor(.white)
                }
            }
            .frame(width: 56, height: 56)
            .goldShine()
            .clipShape(Circle())
        }
        .disabled(startingChat)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    private func startChartChat() async {
        guard !startingChat else { return }
        startingChat = true
        defer { startingChat = false }
        let title = "Chart — \(chatTitleDate())"
        do {
            let conv: ConversationItem = try await api.post(
                "/conversations",
                body: ["title": title, "type": "chart"]
            )
            pendingChatId = conv.id
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("VedicChart", "Failed to start chart chat: \(error)")
                showToast("Couldn't open chat. Please try again.")
            }
        }
    }

    private func chatTitleDate() -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: Date())
    }

    // MARK: - Chart reading (pre-composed from corpus)
    // Card view is in ChartReadingCard.swift.

    private func loadReading(force: Bool = false) async {
        if !force, reading != nil { return }
        if force { reading = nil }
        readingLoading = true
        defer { readingLoading = false }
        do {
            let result: ChartReadingResponse = try await api.get("/jyotish/reading")
            withAnimation(.easeIn(duration: 0.3)) { reading = result }
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("VedicChart", "Failed to load chart reading: \(error)")
            }
        }
    }

    // MARK: - Birth details (editable)

    private var birthDetailsCard: some View {
        SacredCard("BIRTH") {
            VStack(alignment: .leading, spacing: 14) {
                birthRow(
                    icon: Image(systemName: "calendar"),
                    label: birthDate.map { formatBirthDate($0) } ?? "Add birth date",
                    set: birthDate != nil
                ) { showBirthDatePicker = true }

                Divider()

                birthRow(
                    icon: Image(systemName: "clock"),
                    label: birthTime.map { formatBirthTime($0) } ?? "Add birth time",
                    set: birthTime != nil
                ) { showBirthTimePicker = true }

                Divider()

                birthRow(
                    icon: Image(systemName: "mappin.and.ellipse"),
                    label: birthPlaceQuery.isEmpty ? "Add birth place" : birthPlaceQuery,
                    set: !birthPlaceQuery.isEmpty
                ) { showBirthPlacePicker = true }

                if birthDetailsIncomplete {
                    Text("Your chart will appear once all three are filled in.")
                        .font(.sacredMicro)
                        .italic()
                        .foregroundColor(.sacredMuted)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var birthDetailsIncomplete: Bool {
        birthDate == nil || birthTime == nil || birthPlaceQuery.isEmpty
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
                selection: $draftBirthDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding()
            .background(Color.sacredBg.ignoresSafeArea())
            .navigationTitle("Date of birth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showBirthDatePicker = false }
                        .foregroundColor(.sacredMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        birthDate = draftBirthDate
                        showBirthDatePicker = false
                        Task { await saveBirthDetails(); await load() }
                    }
                    .foregroundColor(.sacredGold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var birthTimeSheet: some View {
        NavigationStack {
            DatePicker(
                "Time of birth",
                selection: $draftBirthTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding()
            .background(Color.sacredBg.ignoresSafeArea())
            .navigationTitle("Time of birth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showBirthTimePicker = false }
                        .foregroundColor(.sacredMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        birthTime = draftBirthTime
                        showBirthTimePicker = false
                        Task { await saveBirthDetails(); await load() }
                    }
                    .foregroundColor(.sacredGold)
                }
            }
        }
        .presentationDetents([.medium])
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

                interpretationPanel(key: "nakshatra", concept: JyotishMeanings.nakshatra)
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

                interpretationPanel(key: "lagna", concept: JyotishMeanings.lagna)
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

                interpretationPanel(key: "dasha", concept: JyotishMeanings.dasha)
            }
        }
    }

    private func planetsSection(_ planets: [Planet], hasHouses: Bool) -> some View {
        card(title: "PLANETS") {
            VStack(alignment: .leading, spacing: 14) {
                legendDisclosure
                if hasHouses {
                    groupedByHouse(planets)
                } else {
                    ungroupedPlanets(planets)
                }
            }
        }
    }

    /// Collapsed "What the icons mean" disclosure sitting above the first
    /// planet row — so users encounter the legend BEFORE the icons, not
    /// after scrolling past every planet.
    private var legendDisclosure: some View {
        SacredDisclosure(
            "What the icons mean",
            expandedTitle: "Hide icon key",
            leadingIcon: "sparkles",
            titleStyle: .label,
            isExpanded: disclosureBinding($expanded, key: "legend.root")
        ) {
            legendContent
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

    /// Explains every icon used in the planet rows. Rendered inside
    /// `legendDisclosure` at the TOP of the Planets card (collapsed by
    /// default), so users meet the key before the icons — not after.
    private var legendContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            legendGroup(
                title: "Positive",
                rows: [
                    ("legend.deep_exalted", Image(systemName: "arrow.up.circle.fill"), .sacredGreen, "Deep Exalted",
                     "At the very peak of its strength — a rare placement where the planet's best qualities shine most clearly."),
                    ("legend.exalted", Image(systemName: "arrow.up.circle"), .sacredGreen, "Exalted",
                     "In the sign that amplifies its natural qualities. The planet expresses itself with confidence and ease."),
                    ("legend.moolatrikona", Image(systemName: "crown"), .sacredGreen, "Moolatrikona",
                     "In its honored seat — acts with authority and purpose, deeply connected to its role in the chart."),
                    ("legend.own_sign", Image(systemName: "house"), .sacredGreen, "Own Sign",
                     "The planet is at home. It expresses itself freely and without effort here."),
                    ("legend.vargottama", Image(systemName: "square.grid.2x2"), .sacredGreen, "Vargottama",
                     "The planet occupies the same sign in two key charts — a sign of consistent, reinforced strength.")
                ]
            )
            legendGroup(
                title: "Challenging",
                rows: [
                    ("legend.debilitated", Image(systemName: "arrow.down.circle"), .sacredRed, "Debilitated",
                     "In a sign where it feels out of place. Not a fault — a quiet invitation to grow into this part of life."),
                    ("legend.combust", Image(systemName: "sun.haze"), .sacredRed, "Combust",
                     "Sitting too close to the Sun. Its outward expression is quieter; its energy turns inward rather than broadcasting."),
                    ("legend.sandhi", Image(systemName: "circle.righthalf.filled"), .sacredRed, "Sandhi",
                     "Right at a sign boundary — between two worlds. Its character feels less settled, as if it's in transition.")
                ]
            )
            legendGroup(
                title: "Notable",
                rows: [
                    ("legend.retrograde", Image(systemName: "arrow.uturn.left"), .sacredGold, "Retrograde",
                     "Moving backward through the zodiac at birth. Classically a sign of intensified strength — its themes come through with extra depth.")
                ]
            )
        }
    }

    private func legendGroup(title: String,
                             rows: [(String, Image, Color, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .serif))
                .tracking(2)
                .foregroundColor(.sacredLabel)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    legendRow(key: row.0, icon: row.1, color: row.2, title: row.3, description: row.4)
                }
            }
        }
    }

    /// Single legend entry. Collapsed: icon + name + chevron. Expanded also
    /// shows the plain-language description below.
    private func legendRow(key: String, icon: Image, color: Color,
                           title: String, description: String) -> some View {
        let isOpen = expanded.contains(key)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeOut(duration: 0.2)) {
                    if isOpen { expanded.remove(key) } else { expanded.insert(key) }
                }
            } label: {
                HStack(spacing: 10) {
                    icon
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .foregroundColor(color)
                        .frame(width: 20, alignment: .center)
                    Text(title)
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.sacredText)
                    Spacer(minLength: 0)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold, design: .serif))
                        .foregroundColor(.sacredMuted.opacity(0.6))
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Text(description)
                    .font(.sacredMicro)
                    .italic()
                    .foregroundColor(.sacredTextSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 30)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - What-this-means panel

    /// Expandable disclosure on each chart element — explains what the concept
    /// is (nakshatra / lagna / dasha). The classical passage for the user's
    /// specific placement lives in the top "YOUR READING" card so we don't
    /// repeat it here. Collapsed by default; tap to expand.
    private func interpretationPanel(key: String, concept: String) -> some View {
        SacredDisclosure(
            "What this means",
            expandedTitle: "Hide",
            leadingIcon: "sparkles",
            titleStyle: .label,
            isExpanded: disclosureBinding($expanded, key: key)
        ) {
            Text(concept)
                .font(.sacredSmall)
                .foregroundColor(.sacredTextSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
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

    private func card<Content: View>(title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        SacredCard(title, content: content)
    }

    /// Colors are tiered by classical strength. Opacity runs from 1.0
    /// (strongest/rarest) down to 0.55 (most common/subtle) so a user scanning
    /// the chart can weigh each mark's importance at a glance.
    private func dignityColor(_ dignity: String) -> Color {
        switch dignity {
        case "deep_exalted", "exalted", "moolatrikona", "own_sign": return .sacredGreen
        case "debilitated": return .sacredRed
        default: return .sacredMuted
        }
    }

    /// SF Symbol for each dignity state, matching the legend.
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
                stateGlyph(Image(systemName: "square.grid.2x2"), color: .sacredGreen, label: "Vargottama")
            }
            if p.retrograde == true {
                stateGlyph(Image(systemName: "arrow.uturn.left"), color: .sacredGold, label: "Retrograde")
            }
            if p.combust == true {
                stateGlyph(Image(systemName: "sun.haze"), color: .sacredRed, label: "Combust")
            }
            if p.sandhi == true {
                stateGlyph(Image(systemName: "circle.righthalf.filled"), color: .sacredRed, label: "Sandhi")
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
        VStack(spacing: 14) {
            Text(message)
                .font(.sacredSmall)
                .italic()
                .foregroundColor(.sacredMuted)
                .multilineTextAlignment(.center)
            SacredPrimaryButton("Try again") {
                Task { await load() }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
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
            return "Once your birth date and time are set, your chart will appear here."
        case "invalid_birth_time":
            return "Your birth time couldn't be read — please re-enter it above."
        default:
            return "Your chart will appear here once your birth details are filled in."
        }
    }

    // MARK: - Network

    /// Load birth details first (they seed the UI), then the chart + reading
    /// in parallel. `force: true` is used by pull-to-refresh and the toolbar
    /// button so the reading regenerates even if we already have one cached.
    private func refreshAll(force: Bool) async {
        await loadBirthDetails()
        async let chartLoad: () = load()
        async let readingLoad: () = loadReading(force: force)
        _ = await (chartLoad, readingLoad)
    }

    private func load() async {
        loading = true
        error = nil
        do {
            let result: VedicChart = try await api.get("/jyotish/chart")
            chart = result
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Chart", "Chart load failed: \(error)")
                // Keep the previous chart in view if we have one; only set an
                // error state when we have nothing to show.
                if chart == nil {
                    self.error = "We couldn't load your chart just now."
                } else {
                    showToast("Couldn't refresh just now.")
                }
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
                    // Prefer the user's original display name if we cached it
                    // when they picked — reverse-geocoding loses that fidelity
                    // (small towns become "Locality, Country").
                    if let cached = cachedPlaceName(for: place) {
                        birthPlaceQuery = cached
                    } else {
                        let parts = place.split(separator: ",")
                        if parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]) {
                            let location = CLLocation(latitude: lat, longitude: lng)
                            if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
                                let derived = [placemark.locality, placemark.country]
                                    .compactMap { $0 }
                                    .joined(separator: ", ")
                                birthPlaceQuery = derived
                                if !derived.isEmpty {
                                    cachePlaceName(coords: place, name: derived)
                                }
                            }
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
            // Birth details changed → server-side reading is invalidated.
            // Force a refetch so the user sees the regenerated reading.
            await loadReading(force: true)
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Chart", "Birth save failed: \(error)")
                showToast("Couldn't save. Please try again.")
            }
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
    }

    // MARK: - Formatting

    // Backend only stores "lat,lng" for birthPlace — so we cache the chosen
    // display name locally, keyed by those coords, to preserve the exact
    // label the user picked (e.g. "Kathmandu, Bagmati, Nepal").
    private static let placeNameCacheKey = "chart.birth_place_names"

    private func cachePlaceName(coords: String, name: String) {
        let defaults = UserDefaults.standard
        var cache = defaults.dictionary(forKey: Self.placeNameCacheKey) as? [String: String] ?? [:]
        cache[coords] = name
        defaults.set(cache, forKey: Self.placeNameCacheKey)
    }

    private func cachedPlaceName(for coords: String) -> String? {
        let cache = UserDefaults.standard.dictionary(forKey: Self.placeNameCacheKey) as? [String: String]
        return cache?[coords]
    }

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

// Models moved to VedicChartModels.swift to keep the SwiftUI type checker fast.
