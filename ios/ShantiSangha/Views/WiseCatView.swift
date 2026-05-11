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
    /// When true, sort filtered results by p_buy descending (nulls last).
    /// Default off — search rank follows Finnhub relevance, which is the
    /// "I typed this name, find it" behavior, not a leaderboard.
    @State private var sortByPBuy: Bool = false


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

            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                searchResultsView
            } else {
                ScrollView {
                    VStack(spacing: SacredSpacing.l) {
                        if let plan = vm.plan, plan.positionCount > 0 {
                            summary(plan)
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
        let suggestManual = !trimmed.isEmpty
            && selectedSectors.isEmpty
            && !searchResults.contains(where: { $0.symbol.uppercased() == trimmed })

        VStack(spacing: 0) {
            sortRow
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
                        Text(selectedSectors.isEmpty
                             ? "No matches"
                             : "No matches in the selected sector(s)")
                            .font(.sacredCaption)
                            .foregroundColor(.sacredMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, SacredSpacing.l)
                    }
                }
                .padding(.horizontal, SacredSpacing.m)
                .padding(.top, SacredSpacing.m)
                .padding(.bottom, SacredSpacing.tabBarSafe)
            }
        }
    }

    /// Compact sort toggle. Off = Finnhub relevance order (typing a name
    /// finds it). On = p_buy descending, nulls last. The on-state is a
    /// deliberate user choice — we never default to it, because that
    /// would re-create the "highest-buy-rating" leaderboard.
    private var sortRow: some View {
        HStack(spacing: SacredSpacing.xs) {
            Spacer()
            Button {
                sortByPBuy.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: sortByPBuy ? "arrow.down.right.circle.fill" : "arrow.down.right.circle")
                        .font(.system(size: 12))
                    Text(sortByPBuy ? "Sorted by buy rating" : "Sort by buy rating")
                        .font(.sacredCaption)
                }
                .foregroundColor(sortByPBuy ? .sacredGold : .sacredTextSecondary)
                .padding(.horizontal, SacredSpacing.s)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(sortByPBuy ? Color.sacredGold.opacity(0.12) : Color.clear)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SacredSpacing.m)
        .padding(.top, SacredSpacing.xs)
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

    private func filteredResults(heldSet: Set<String>) -> [SymbolMatch] {
        let filtered: [SymbolMatch] = {
            if selectedSectors.isEmpty { return searchResults }
            return searchResults.filter { match in
                guard let s = match.sector else { return false }
                return selectedSectors.contains(s)
            }
        }()
        if !sortByPBuy { return filtered }
        return filtered.sorted { lhs, rhs in
            // nulls last; otherwise higher p_buy first.
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
    /// the latest query wins.
    private func scheduleSearch(for raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            searchResults = []
            searching = false
            return
        }
        let id = UUID()
        searchTaskID = id
        searching = true
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard searchTaskID == id else { return }
            do {
                let hits = try await WiseCatAPI.searchSymbolsEnriched(trimmed, limit: 12)
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
