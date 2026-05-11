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
                            buysSection(plan)
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
        if selectedSectors.isEmpty { return searchResults }
        return searchResults.filter { match in
            guard let s = match.sector else { return false }   // hide unscored when filtering
            return selectedSectors.contains(s)
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
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
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
                    sectorBadge(plan)
                }
                Text("\(plan.positionCount) positions · \(money(plan.cashBalance)) cash")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredTextSecondary)
            }
            .padding(SacredSpacing.lux)
        }
    }

    private func sectorBadge(_ plan: PortfolioPlan) -> some View {
        let ok = plan.sectorsCovered >= plan.minSectorsRequired
        let label = "\(plan.sectorsCovered)/\(plan.minSectorsRequired)+ sectors"
        return Text(label)
            .font(.sacredSmallSemibold)
            .foregroundColor(ok ? .sacredGreen : .sacredRed)
            .padding(.horizontal, SacredSpacing.s)
            .padding(.vertical, SacredSpacing.xxs)
            .background(
                Capsule()
                    .fill((ok ? Color.sacredGreen : Color.sacredRed).opacity(0.12))
            )
    }

    @ViewBuilder
    private func holdingsSection(_ plan: PortfolioPlan) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            Text("Your holdings")
                .font(.sacredSubheading)
                .foregroundColor(.sacredText)

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
    }

    @ViewBuilder
    private func buysSection(_ plan: PortfolioPlan) -> some View {
        let buys = plan.actions.filter { $0.kind == .buy }
        if !buys.isEmpty {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                Text("Recommended buys")
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)

                VStack(spacing: 0) {
                    ForEach(Array(buys.enumerated()), id: \.element.id) { index, action in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.sacredMuted.opacity(0.18))
                                .frame(height: 1)
                        }
                        BuyRow(action: action)
                    }
                }
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
                    if let reason = compactReason {
                        Text(reason)
                            .font(.sacredCaption)
                            .foregroundColor(.sacredMuted)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
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

    /// Short reason hint for SELL / TRIM rows.
    private var compactReason: String? {
        guard let action else { return nil }
        switch action.kind {
        case .sell:
            if holding.unrealizedReturnPct >= 0.10 { return "Hit +10% target" }
            if holding.unrealizedReturnPct <= -0.10 { return "Past -10% stop" }
            if holding.pSell >= 0.55 { return "Model: exit signal" }
            return "Rule violation"
        case .trim:
            return "Over 10% cap"
        case .hold, .buy:
            return nil
        }
    }
}

private struct BuyRow: View {
    let action: PortfolioAction

    var body: some View {
        NavigationLink(destination: WiseCatDetailView(ticker: action.ticker)) {
            VStack(alignment: .leading, spacing: SacredSpacing.s) {
                HStack(alignment: .center, spacing: SacredSpacing.m) {
                    VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                        Text(action.ticker)
                            .font(.sacredHeading)
                            .foregroundColor(.sacredText)
                        Text(action.sector)
                            .font(.sacredSmall)
                            .foregroundColor(.sacredTextSecondary)
                        if let price = action.price, price > 0 {
                            Text(String(format: "$%.2f", price))
                                .font(.sacredCaption)
                                .foregroundColor(.sacredMuted)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: SacredSpacing.xxs) {
                        Text("BUY")
                            .font(.sacredButtonLabel)
                            .foregroundColor(.sacredGreen)
                        if let amount = action.amount, amount > 0 {
                            Text(target(amount))
                                .font(.sacredCaption)
                                .foregroundColor(.sacredTextSecondary)
                        }
                        Text(shortReason)
                            .font(.sacredCaption)
                            .foregroundColor(.sacredMuted)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }

                if let bracket = action.bracket {
                    bracketChips(bracket)
                }
            }
            .padding(.vertical, SacredSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Three compact chips — entry / stop / target — plus an R-multiple
    /// caption so the user can see the trade's reward-to-risk shape
    /// before placing the bracket at their broker.
    @ViewBuilder
    private func bracketChips(_ b: BracketOrder) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
            HStack(spacing: SacredSpacing.xs) {
                bracketChip(label: "Entry", value: String(format: "$%.2f", b.entryPrice),
                            tint: .sacredText)
                bracketChip(label: "Stop", value: String(format: "$%.2f", b.stopPrice),
                            tint: .sacredRed)
                bracketChip(label: "Target", value: String(format: "$%.2f", b.targetPrice),
                            tint: .sacredGreen)
            }
            Text(String(format: "Risk $%.0f per share, $%.0f total · %.1fR",
                        b.riskPerShare, b.totalRiskDollars, b.rMultiple))
                .font(.sacredCaption)
                .foregroundColor(.sacredMuted)
        }
    }

    private func bracketChip(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.sacredCaption)
                .foregroundColor(.sacredMuted)
            Text(value)
                .font(.sacredSmallSemibold)
                .foregroundColor(tint)
        }
        .padding(.horizontal, SacredSpacing.xs)
        .padding(.vertical, SacredSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.sacredBgCard.opacity(0.6))
        )
    }

    private func target(_ v: Double) -> String {
        if v >= 1000 { return String(format: "~$%.1fk", v / 1000) }
        return String(format: "~$%.0f", v)
    }

    /// Distill the server reason into 1-2 line hint.
    private var shortReason: String {
        let r = action.reason.lowercased()
        if r.contains("high-confidence") { return "High conf · missing sector" }
        if r.contains("missing sector") { return "Missing sector · low conf" }
        return action.reason
    }
}
