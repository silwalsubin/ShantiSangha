import SwiftUI

/// Stocks tab. Renders the user's portfolio plan: holdings with action
/// badges (HOLD / SELL / TRIM) + recommended buys against the 10-rule
/// Mode B strategy. The watchlist concept is hidden — held tickers
/// auto-sync to the watchlist on the server so the daily-signal cron
/// keeps firing for them.
struct WiseCatView: View {
    @StateObject private var vm = PortfolioViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showRules = false
    @State private var pendingDelete: String?
    @State private var lastFetchAt: Date?

    // Global ticker search (replaces the old "+" button — search is the
    // new entry point for both navigating to held tickers and adding new
    // positions).
    @State private var query = ""
    @State private var searchResults: [SymbolMatch] = []
    @State private var searching = false
    @State private var searchTaskID = UUID()
    @State private var selectedSectors: Set<String> = []
    @State private var selectedPBuyBuckets: Set<PBuyBucket> = []
    /// Watching section is collapsed by default; the user expands it
    /// when they want to see what they're tracking. State lives on the
    /// view because it's a pure UI preference.
    @State private var watchlistExpanded: Bool = false

    /// Buckets that match how p_buy actually distributes in our model
    /// output. When any bucket is active, results are filtered to the
    /// union of selected ranges AND auto-sorted by p_buy descending so
    /// the strongest candidate within the selection floats up.
    enum PBuyBucket: String, CaseIterable, Hashable {
        case lt50, fifty, sixty, seventy

        var label: String {
            switch self {
            case .lt50:    return "< 50"
            case .fifty:   return "50–60"
            case .sixty:   return "60–70"
            case .seventy: return "70+"
            }
        }
        func contains(_ pBuy: Double) -> Bool {
            let pct = pBuy * 100
            switch self {
            case .lt50:    return pct < 50
            case .fifty:   return pct >= 50 && pct < 60
            case .sixty:   return pct >= 60 && pct < 70
            case .seventy: return pct >= 70
            }
        }
    }


    /// GICS-11 sector universe. Static (rather than derived from results)
    /// so the filter chips don't reflow on every keystroke.
    private let sectorFilters: [String] = [
        "Information Technology", "Health Care", "Financials",
        "Consumer Discretionary", "Consumer Staples", "Communication Services",
        "Industrials", "Energy", "Utilities", "Materials", "Real Estate",
    ]

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            // Switch between portfolio and search-results panel based on
            // both the typed query AND the search bar's focus. Reading
            // `\.isSearching` requires being a descendant of the
            // `.searchable()` modifier, hence the SearchActiveAware shim.
            SearchActiveAware { isSearching in
                let typing = !query.trimmingCharacters(in: .whitespaces).isEmpty
                if isSearching || typing {
                    searchResultsView
                } else {
                    ScrollView {
                        VStack(spacing: SacredSpacing.l) {
                            if let plan = vm.plan, plan.positionCount > 0 {
                                summary(plan)
                                if !vm.watchlist.isEmpty {
                                    watchingSection
                                }
                                holdingsSection(plan)
                            } else if vm.generatingPlan || vm.loading {
                                ProgressView()
                                    .tint(.sacredGold)
                                    .frame(maxWidth: .infinity, minHeight: 200)
                            } else {
                                emptyState
                            }

                            if let err = vm.error {
                                Text(err)
                                    .font(.sacredCaption)
                                    .foregroundColor(.sacredRed)
                                    .padding(.horizontal, SacredSpacing.m)
                            }
                        }
                        .padding(.horizontal, SacredSpacing.m)
                        .padding(.top, SacredSpacing.l)
                        .padding(.bottom, SacredSpacing.tabBarSafe)
                    }
                    .refreshable {
                        // User-driven refresh — bypass throttle entirely.
                        lastFetchAt = Date()
                        await vm.generatePlan()
                    }
                }
            }
        }
        .navigationTitle("Stocks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRules = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.sacredGold)
                }
                .accessibilityLabel("Edit rules")
            }
        }
        .searchable(text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search a stock"))
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled(true)
        .onChange(of: query) { _, newValue in
            scheduleSearch(for: newValue)
        }
        .sheet(isPresented: $showRules, onDismiss: {
            // Rule changes shift the plan output — regenerate.
            Task { await vm.generatePlan() }
        }) {
            StrategyRulesView()
        }
        .confirmationDialog("Remove this position?",
                            isPresented: Binding(
                                get: { pendingDelete != nil },
                                set: { if !$0 { pendingDelete = nil } }
                            ),
                            titleVisibility: .visible) {
            Button("Remove \(pendingDelete ?? "")", role: .destructive) {
                if let t = pendingDelete {
                    Task { await vm.removePosition(t) }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Your shares and cost basis will be deleted. The position can be re-added later.")
        }
        .task {
            await refresh(force: true)
        }
        .onAppear {
            // Tab switch or NavigationLink return — refresh if data is older
            // than ~5s. Tight enough that returning from a detail-view "Add
            // to portfolio" surfaces the new position immediately; the
            // pull-to-refresh and scene-phase paths cover everything else.
            Task { await refresh(force: false, maxAgeSeconds: 5) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Background → foreground: always refresh, the prices and
            // model output are likely stale.
            if newPhase == .active {
                Task { await refresh(force: true) }
            }
        }
    }

    private func refresh(force: Bool, maxAgeSeconds: TimeInterval = 30) async {
        if !force, let last = lastFetchAt,
           Date().timeIntervalSince(last) < maxAgeSeconds {
            return
        }
        lastFetchAt = Date()
        await vm.loadPortfolio()
        await vm.generatePlan()
        await vm.loadWatchlist()
    }

    // MARK: - Search

    /// Search-results screen that takes over the main scroll content
    /// while the user is typing. Held tickers push to detail; new
    /// tickers open AddPositionView pre-filled with that symbol. When
    /// no Finnhub match comes back, an "Add <QUERY> manually" fallback
    /// keeps the escape hatch open.
    @ViewBuilder
    private var searchResultsView: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces).uppercased()
        let heldSet = Set(vm.positions.map { $0.ticker.uppercased() })
        let filtered = filteredResults(heldSet: heldSet)
        let manualSymbol = SymbolMatch(symbol: trimmed, description: "", type: "")
        let filtersActive = !selectedSectors.isEmpty || !selectedPBuyBuckets.isEmpty
        let suggestManual = !trimmed.isEmpty
            && !filtersActive
            && !searchResults.contains(where: { $0.symbol.uppercased() == trimmed })

        VStack(spacing: 0) {
            pBuyBucketRow
            sectorFilterRow

            ScrollView {
                VStack(spacing: SacredSpacing.s) {
                    if searching && filtered.isEmpty {
                        ProgressView()
                            .tint(.sacredGold)
                            .padding(.top, SacredSpacing.l)
                    }

                    ForEach(filtered) { match in
                        searchResultRow(match: match,
                                        held: heldSet.contains(match.symbol.uppercased()))
                    }

                    if suggestManual {
                        searchResultRow(match: manualSymbol,
                                        held: heldSet.contains(trimmed),
                                        manualFallback: true)
                    }

                    if !searching && filtered.isEmpty && !suggestManual {
                        Text(emptyResultsCopy(trimmed: trimmed, filtersActive: filtersActive))
                            .font(.sacredCaption)
                            .foregroundColor(.sacredMuted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, SacredSpacing.m)
                            .padding(.top, SacredSpacing.l)
                    }
                }
                .padding(.horizontal, SacredSpacing.m)
                .padding(.top, SacredSpacing.m)
                .padding(.bottom, SacredSpacing.tabBarSafe)
            }
        }
        .onAppear {
            // First-touch of the search panel — fire a browse fetch so
            // the filter chips have something to narrow when the user
            // hasn't typed yet. Idempotent thanks to scheduleSearch's
            // ID-based cancellation; subsequent appearances re-fetch
            // only if we don't already have results loaded.
            if searchResults.isEmpty {
                scheduleSearch(for: query)
            }
        }
    }

    /// Buy-rating bucket chips. Tap one or more to filter; OR semantics
    /// within the bucket row, AND against the sector chip row. When any
    /// bucket is active, results are auto-sorted by p_buy descending
    /// inside the filtered set so the strongest candidate floats up.
    /// Unscored rows (no cached bars) are hidden whenever any bucket is
    /// active — they have no rating, no honest place to land.
    private var pBuyBucketRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SacredSpacing.xs) {
                Text("BUY RATING")
                    .font(.sacredSectionLabel)
                    .foregroundColor(.sacredMuted)
                ForEach(PBuyBucket.allCases, id: \.self) { bucket in
                    pBuyBucketChip(bucket)
                }
            }
            .padding(.horizontal, SacredSpacing.m)
            .padding(.vertical, SacredSpacing.xs)
        }
    }

    private func pBuyBucketChip(_ bucket: PBuyBucket) -> some View {
        let active = selectedPBuyBuckets.contains(bucket)
        // Mirror the result-row chip tint so the bucket choice has the
        // same visual language as the per-row p_buy chip.
        let tint: Color = {
            switch bucket {
            case .lt50:    return .sacredMuted
            case .fifty:   return .sacredGold
            case .sixty:   return .sacredGreen
            case .seventy: return .sacredGreen
            }
        }()
        return Button {
            if active { selectedPBuyBuckets.remove(bucket) }
            else { selectedPBuyBuckets.insert(bucket) }
        } label: {
            Text(bucket.label)
                .font(.sacredSmallSemibold)
                .foregroundColor(active ? .white : tint)
                .padding(.horizontal, SacredSpacing.s)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(active ? tint : Color.sacredBgCard.opacity(0.6))
                )
                .overlay(
                    Capsule()
                        .stroke(active ? Color.clear : tint.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    /// Horizontal chips along the top of search mode. Tapping a chip
    /// toggles it; multiple chips can be active (OR semantics). An
    /// unscored row (no sector resolved) is hidden whenever any chip is
    /// active — better to hide than to lie about its sector.
    private var sectorFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SacredSpacing.xs) {
                ForEach(sectorFilters, id: \.self) { sector in
                    sectorChip(sector)
                }
            }
            .padding(.horizontal, SacredSpacing.m)
            .padding(.vertical, SacredSpacing.xs)
        }
    }

    private func sectorChip(_ sector: String) -> some View {
        let active = selectedSectors.contains(sector)
        return Button {
            if active { selectedSectors.remove(sector) }
            else { selectedSectors.insert(sector) }
        } label: {
            Text(sector)
                .font(.sacredSmallSemibold)
                .foregroundColor(active ? .white : .sacredText)
                .padding(.horizontal, SacredSpacing.s)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(active ? Color.sacredGold : Color.sacredBgCard.opacity(0.6))
                )
                .overlay(
                    Capsule()
                        .stroke(active ? Color.clear : Color.sacredMuted.opacity(0.25),
                                lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    /// Empty-state copy. Browse mode (empty query) loads the held +
    /// basket universe on appear, so "nothing showing" almost always
    /// means the filter chips narrowed the set to zero.
    private func emptyResultsCopy(trimmed: String, filtersActive: Bool) -> String {
        filtersActive
            ? "No matches with the active filters"
            : "No matches"
    }

    private func filteredResults(heldSet: Set<String>) -> [SymbolMatch] {
        // Sector filter — hide unscored rows when active.
        let bySector: [SymbolMatch] = {
            if selectedSectors.isEmpty { return searchResults }
            return searchResults.filter { match in
                guard let s = match.sector else { return false }
                return selectedSectors.contains(s)
            }
        }()

        // p_buy bucket filter — hide unscored rows when active.
        let byBucket: [SymbolMatch] = {
            if selectedPBuyBuckets.isEmpty { return bySector }
            return bySector.filter { match in
                guard let pBuy = match.pBuy else { return false }
                return selectedPBuyBuckets.contains(where: { $0.contains(pBuy) })
            }
        }()

        // When the user has narrowed by bucket, sort strongest-first
        // within the selection — that's the implicit ask. Otherwise
        // preserve Finnhub relevance order so "I typed AAPL" finds AAPL.
        if selectedPBuyBuckets.isEmpty { return byBucket }
        return byBucket.sorted { lhs, rhs in
            switch (lhs.pBuy, rhs.pBuy) {
            case let (l?, r?): return l > r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return false
            }
        }
    }

    @ViewBuilder
    private func searchResultRow(match: SymbolMatch,
                                 held: Bool,
                                 manualFallback: Bool = false) -> some View
    {
        // Both held and not-held tap into the detail view. The detail view
        // surfaces an "Add to portfolio" CTA at the bottom when the ticker
        // isn't already owned, so the user sees the full chart + signals
        // BEFORE committing capital.
        NavigationLink(destination: WiseCatDetailView(ticker: match.symbol)) {
            searchRowContent(match: match, held: held, manualFallback: manualFallback)
        }
        .buttonStyle(.plain)
    }

    private func searchRowContent(match: SymbolMatch,
                                  held: Bool,
                                  manualFallback: Bool) -> some View
    {
        LuxCard {
            HStack(alignment: .center, spacing: SacredSpacing.m) {
                VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                    Text(match.symbol.uppercased())
                        .font(.sacredHeading)
                        .foregroundColor(.sacredText)
                    if !match.description.isEmpty {
                        Text(match.description)
                            .font(.sacredCaption)
                            .foregroundColor(.sacredTextSecondary)
                            .lineLimit(1)
                    } else if manualFallback {
                        Text("Add manually — not in symbol search")
                            .font(.sacredCaption)
                            .foregroundColor(.sacredMuted)
                    }
                    if let sector = match.sector, !sector.isEmpty {
                        Text(sector)
                            .font(.sacredCaption)
                            .foregroundColor(.sacredMuted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: SacredSpacing.xxs) {
                    if held {
                        Text("IN PORTFOLIO")
                            .font(.sacredCaption)
                            .foregroundColor(.sacredGold)
                    } else if !manualFallback {
                        Text("VIEW")
                            .font(.sacredButtonLabel)
                            .foregroundColor(.sacredGold)
                    } else {
                        Text("ADD")
                            .font(.sacredButtonLabel)
                            .foregroundColor(.sacredGreen)
                    }
                    if let pBuy = match.pBuy, let horizon = match.horizon {
                        probabilityChip(pBuy: pBuy, horizon: horizon)
                    }
                }
            }
            .padding(SacredSpacing.lux)
            .frame(minHeight: 44)
        }
    }

    /// Compact p_buy chip. Color is informational only — tinted by
    /// strength bucket so the user can scan a list without inviting a
    /// "highest first" leaderboard sort.
    private func probabilityChip(pBuy: Double, horizon: String) -> some View {
        let tint: Color = {
            if pBuy >= 0.60 { return .sacredGreen }
            if pBuy >= 0.50 { return .sacredGold }
            return .sacredMuted
        }()
        return Text(String(format: "p_buy %.2f · %@", pBuy, horizon as NSString))
            .font(.sacredCaption)
            .foregroundColor(tint)
    }

    /// Cancellable, lightly-debounced search. Each keystroke spawns a
    /// task that waits 250ms before hitting the symbol-search endpoint;
    /// the previous task is cancelled by bumping `searchTaskID` so only
    /// the latest query wins. An empty query is NOT a no-op — the
    /// backend's browse mode kicks in and returns the held + sector-
    /// basket universe so the filter chips can stand alone.
    private func scheduleSearch(for raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let id = UUID()
        searchTaskID = id
        searching = true
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard searchTaskID == id else { return }
            do {
                // Browse mode wants a wider cap; typed-query mode stays
                // narrow so Finnhub relevance order remains useful.
                let limit = trimmed.isEmpty ? 30 : 12
                let hits = try await WiseCatAPI.searchSymbolsEnriched(trimmed, limit: limit)
                guard searchTaskID == id else { return }
                await MainActor.run {
                    self.searchResults = hits
                    self.searching = false
                }
            } catch {
                guard searchTaskID == id else { return }
                await MainActor.run {
                    self.searchResults = []
                    self.searching = false
                }
            }
        }
    }

    // MARK: - Sections

    private func summary(_ plan: PortfolioPlan) -> some View {
        let missingPicks = plan.actions
            .filter { $0.kind == .buy && $0.bracket != nil && plan.missingSectors.contains($0.sector) }

        return VStack(alignment: .leading, spacing: SacredSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Portfolio")
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.sacredMuted)
                    Text(money(plan.totalValue))
                        .font(.sacredTitle)
                        .foregroundColor(.sacredText)
                }
                Spacer()
                sectorBadge(plan, missingPicks: missingPicks)
            }
            Text("\(plan.positionCount) positions · \(money(plan.cashBalance)) cash")
                .font(.sacredSmall)
                .foregroundColor(.sacredTextSecondary)
        }
    }

    private func sectorBadge(_ plan: PortfolioPlan,
                             missingPicks: [PortfolioAction]) -> some View
    {
        let ok = plan.sectorsCovered >= plan.minSectorsRequired
        let label = "\(plan.sectorsCovered)/\(plan.minSectorsRequired)+ sectors"
        let tint: Color = ok ? .sacredGreen : .sacredRed
        let shortfall = max(0, plan.minSectorsRequired - plan.sectorsCovered)
        let explanation = ok
            ? "You're covering \(plan.sectorsCovered) sectors — diversification is intact."
            : "Spread risk across at least \(plan.minSectorsRequired) sectors. You're holding \(plan.sectorsCovered) — \(shortfall) short. Diversification is what protects you when one sector takes a hit."

        return SacredStatusBadge(label: label, tint: tint) {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                Text(explanation)
                    .font(.sacredText)
                    .foregroundColor(.sacredText)
                    .fixedSize(horizontal: false, vertical: true)
                if !missingPicks.isEmpty {
                    Text("MISSING")
                        .font(.sacredSectionLabel)
                        .foregroundColor(.sacredMuted)
                        .padding(.top, SacredSpacing.xxs)
                    Text(missingPicks.map { $0.sector }.joined(separator: ", "))
                        .font(.sacredCaption)
                        .foregroundColor(.sacredTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Collapsible "Watching" section between summary and holdings.
    /// Default collapsed — header shows the count and a chevron. Tap
    /// header to expand. Each row is a thin holding-style line (ticker,
    /// sector, p_buy badge) and pushes to the detail view on tap.
    @ViewBuilder
    private var watchingSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    watchlistExpanded.toggle()
                }
            } label: {
                HStack(spacing: SacredSpacing.xs) {
                    Text("Watching \(vm.watchlist.count)")
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.sacredTextSecondary)
                    Spacer()
                    Image(systemName: watchlistExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.sacredMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if watchlistExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(vm.watchlist.enumerated()), id: \.element.id) { index, match in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.sacredMuted.opacity(0.18))
                                .frame(height: 1)
                        }
                        WatchRow(match: match) {
                            await unwatch(match.symbol)
                        }
                    }
                }
            }
        }
    }

    private func unwatch(_ ticker: String) async {
        do {
            try await WiseCatAPI.removeWatchlist(ticker)
            await vm.loadWatchlist()
        } catch {
            // Silent — surfacing a banner for a swipe-delete failure
            // would feel noisy; the row reappears on next refresh.
        }
    }

    @ViewBuilder
    private func holdingsSection(_ plan: PortfolioPlan) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(plan.holdings.enumerated()), id: \.element.id) { index, holding in
                if index > 0 {
                    Rectangle()
                        .fill(Color.sacredMuted.opacity(0.18))
                        .frame(height: 1)
                }
                HoldingRow(
                    holding: holding,
                    action: action(for: holding.ticker, in: plan),
                    onRequestDelete: { pendingDelete = holding.ticker }
                )
            }
        }
    }

    private var emptyState: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.s) {
                Text("Build your portfolio")
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
                Text("Search a ticker above to add your first position (you'll enter shares + cost per share). The app then tells you what to hold, trim, sell, and which sectors to fill.")
                    .font(.sacredText)
                    .foregroundColor(.sacredTextSecondary)
            }
            .padding(SacredSpacing.lux)
        }
    }

    // MARK: - Helpers

    private func action(for ticker: String, in plan: PortfolioPlan) -> PortfolioAction? {
        plan.actions.first(where: { $0.ticker == ticker && $0.kind != .buy })
    }

    private func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Rows

/// Reads `\.isSearching` from the environment and surfaces it to a
/// closure. SwiftUI only propagates that value to descendants of the
/// `.searchable()` modifier, so the parent view can't read it directly
/// — this view does.
private struct SearchActiveAware<Content: View>: View {
    @Environment(\.isSearching) private var isSearching
    @ViewBuilder let content: (Bool) -> Content
    var body: some View { content(isSearching) }
}

/// Single-row layout for the "Watching" section: ticker, sector, p_buy
/// chip on the right. Tap = detail view. Swipe trailing or long-press
/// gives an "Unwatch" action via the same callback.
private struct WatchRow: View {
    let match: SymbolMatch
    var onUnwatch: () async -> Void

    var body: some View {
        NavigationLink(destination: WiseCatDetailView(ticker: match.symbol)) {
            HStack(alignment: .center, spacing: SacredSpacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.symbol)
                        .font(.sacredTextSemibold)
                        .foregroundColor(.sacredText)
                    if let sector = match.sector, !sector.isEmpty {
                        Text(sector)
                            .font(.sacredCaption)
                            .foregroundColor(.sacredTextSecondary)
                    }
                }
                Spacer()
                if let pBuy = match.pBuy, let horizon = match.horizon {
                    probabilityChip(pBuy: pBuy, horizon: horizon)
                }
            }
            .padding(.vertical, SacredSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await onUnwatch() }
            } label: { Label("Unwatch", systemImage: "star.slash") }
        }
        .contextMenu {
            Button(role: .destructive) {
                Task { await onUnwatch() }
            } label: { Label("Unwatch", systemImage: "star.slash") }
        }
    }

    private func probabilityChip(pBuy: Double, horizon: String) -> some View {
        let tint: Color = {
            if pBuy >= 0.60 { return .sacredGreen }
            if pBuy >= 0.50 { return .sacredGold }
            return .sacredMuted
        }()
        return Text(String(format: "p_buy %.2f · %@", pBuy, horizon as NSString))
            .font(.sacredCaption)
            .foregroundColor(tint)
    }
}

private struct HoldingRow: View {
    let holding: PortfolioHolding
    let action: PortfolioAction?
    var onRequestDelete: () -> Void

    var body: some View {
        NavigationLink(destination: WiseCatDetailView(ticker: holding.ticker)) {
            HStack(alignment: .center, spacing: SacredSpacing.m) {
                VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                    Text(holding.ticker)
                        .font(.sacredHeading)
                        .foregroundColor(.sacredText)
                    Text(metaLine)
                        .font(.sacredSmall)
                        .foregroundColor(.sacredTextSecondary)
                    Text(unrealizedLine)
                        .font(.sacredCaption)
                        .foregroundColor(holding.unrealizedReturnPct >= 0 ? .sacredGreen : .sacredRed)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: SacredSpacing.xxs) {
                    Text(actionBadge)
                        .font(.sacredButtonLabel)
                        .foregroundColor(actionColor)
                    ProbabilityBar(
                        pBuy: holding.pBuy,
                        pHold: max(0, 1 - holding.pBuy - holding.pSell),
                        pSell: holding.pSell,
                        height: 8,
                        showLabels: false
                    )
                    .frame(width: 120)
                    if let badge = compactReasonBadge {
                        SacredStatusBadge(label: badge.label,
                                          tint: badge.tint,
                                          explanation: badge.explanation)
                    }
                }
            }
            .padding(.vertical, SacredSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onRequestDelete) {
                Label("Remove", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onRequestDelete) {
                Label("Remove position", systemImage: "trash")
            }
        }
    }

    private var metaLine: String {
        let priceStr = String(format: "$%.2f", holding.currentPrice)
        let pctPort = String(format: "%.1f%%", holding.percentOfPortfolio * 100)
        return "\(priceStr) · \(pctPort) · \(holding.sector)"
    }

    private var unrealizedLine: String {
        let cost = holding.shares * holding.costBasis
        let dollarPnL = holding.marketValue - cost
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = (abs(dollarPnL) >= 1000) ? 0 : 2
        let formatted = f.string(from: NSNumber(value: abs(dollarPnL))) ?? "$\(abs(Int(dollarPnL)))"
        let sign = dollarPnL >= 0 ? "+" : "-"
        return "\(sign)\(formatted)"
    }

    private var actionBadge: String {
        guard let action else { return "HOLD" }
        switch action.kind {
        case .sell: return "SELL"
        case .trim: return "TRIM"
        case .hold: return "HOLD"
        case .buy:  return "HOLD"  // shouldn't happen for held tickers
        }
    }

    private var actionColor: Color {
        guard let action else { return .sacredText }
        switch action.kind {
        case .sell:
            // Profit-taking exits read green even though the verb is still
            // SELL — celebrates the win rather than punishing the row.
            return holding.unrealizedReturnPct >= 0.10 ? .sacredGreen : .sacredRed
        case .trim: return .sacredGoldDark
        case .hold: return .sacredText
        case .buy:  return .sacredGreen
        }
    }

    /// Status pill rendered under the action label on SELL / TRIM rows.
    /// The label is the "what"; the explanation is shown when the pill
    /// is tapped, surfaced through `SacredStatusBadge`. Reasons mirror
    /// the rule constants the PortfolioService is actually enforcing
    /// (Rule 3 stop, Rule 11 take-profit, Rule 2 concentration cap).
    private var compactReasonBadge: (label: String, tint: Color, explanation: String)? {
        guard let action else { return nil }
        switch action.kind {
        case .sell:
            if holding.unrealizedReturnPct >= 0.10 {
                return (
                    label: "Hit target",
                    tint: .sacredGreen,
                    explanation: "This position has reached your take-profit threshold (default +10% from cost). Cashing out locks in the win and frees the slot for the next signal."
                )
            }
            if holding.unrealizedReturnPct <= -0.07 {
                return (
                    label: "Past stop",
                    tint: .sacredRed,
                    explanation: "This position is down past your stop-loss threshold (default -7% from cost). Exiting at the pre-committed stop is the discipline that prevents another large drawdown."
                )
            }
            if holding.pSell >= 0.55 {
                return (
                    label: "Exit signal",
                    tint: .sacredRed,
                    explanation: "The WiseCat model's exit confidence crossed the advisory threshold (default 0.55). The momentum read has flipped bearish at your entry horizon."
                )
            }
            return (
                label: "Exit triggered",
                tint: .sacredRed,
                explanation: "One of your exit conditions fired against this position. Open the detail view to see which signal triggered it."
            )
        case .trim:
            return (
                label: "Over cap",
                tint: .sacredGoldDark,
                explanation: "Each position is capped at 10% of the portfolio. This holding has grown past the cap — trim back to the target to keep concentration risk bounded."
            )
        case .hold, .buy:
            return nil
        }
    }
}
