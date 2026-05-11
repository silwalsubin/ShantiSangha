import SwiftUI

/// Focused single-purpose flow: pick a ticker via symbol search, enter
/// shares + cost basis, save. Presented as a modal sheet from the
/// Stocks tab's "+" toolbar button.
struct AddPositionView: View {
    /// Tickers already in the user's portfolio — disabled in the search
    /// step so the user doesn't try to "add" a duplicate (the backend
    /// would reject anyway).
    var excludedTickers: Set<String>
    /// Pre-selected ticker. When non-nil the view opens directly on the
    /// cost-basis form step and skips symbol search. Cancel still backs
    /// out of the sheet entirely (no search step to fall back to).
    var prefilledTicker: String?
    /// Called when a position is successfully saved. Parent should
    /// regenerate the plan and dismiss the sheet.
    var onSaved: () -> Void

    init(excludedTickers: Set<String>,
         prefilledTicker: String? = nil,
         onSaved: @escaping () -> Void)
    {
        self.excludedTickers = excludedTickers
        self.prefilledTicker = prefilledTicker
        self.onSaved = onSaved
        _picked = State(initialValue: prefilledTicker?.uppercased())
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = PortfolioViewModel()

    @State private var picked: String?
    @State private var sharesText: String = ""
    @State private var costText: String = ""
    @State private var saving = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                SacredBackground()
                    .ignoresSafeArea()

                if let picked {
                    formStep(ticker: picked)
                } else {
                    TickerSearchSheetEmbedded(excluded: excludedTickers) { symbol in
                        self.picked = symbol
                    }
                }
            }
            .navigationTitle(picked == nil ? "Add a stock" : (picked ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        // When prefilled we have no search step to fall back
                        // to, so Cancel always dismisses the sheet outright.
                        if picked != nil && prefilledTicker == nil {
                            picked = nil
                            sharesText = ""
                            costText = ""
                            localError = nil
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundColor(.sacredGold)
                }
            }
        }
    }

    // MARK: - Form step

    private func formStep(ticker: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SacredSpacing.l) {
                explanation(ticker: ticker)

                LuxCard {
                    VStack(alignment: .leading, spacing: SacredSpacing.m) {
                        labeledField(label: "Shares you own",
                                     text: $sharesText,
                                     placeholder: "0")
                        Divider()
                            .background(Color.sacredMuted.opacity(0.18))
                        labeledField(label: "Cost per share (USD)",
                                     text: $costText,
                                     placeholder: "0.00")
                    }
                    .padding(SacredSpacing.lux)
                }

                if let err = localError ?? vm.error {
                    Text(err)
                        .font(.sacredCaption)
                        .foregroundColor(.sacredRed)
                }

                saveButton(ticker: ticker)
            }
            .padding(.horizontal, SacredSpacing.m)
            .padding(.top, SacredSpacing.l)
            .padding(.bottom, SacredSpacing.tabBarSafe)
        }
    }

    private func explanation(ticker: String) -> some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                Text("How much, and at what cost?")
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
                Text("Enter the number of \(ticker) shares you currently own and the average cost you paid per share. The plan uses cost to track P&L against the -10% stop rule.")
                    .font(.sacredText)
                    .foregroundColor(.sacredTextSecondary)
            }
            .padding(SacredSpacing.lux)
        }
    }

    private func labeledField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
            Text(label)
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredTextSecondary)
            TextField(placeholder, text: text)
                .font(.sacredHeading)
                .foregroundColor(.sacredText)
                .keyboardType(.decimalPad)
        }
    }

    private func saveButton(ticker: String) -> some View {
        Button {
            Task { await save(ticker: ticker) }
        } label: {
            HStack {
                Spacer()
                if saving {
                    ProgressView().tint(.white)
                } else {
                    Text("Add to portfolio")
                        .font(.sacredButtonLabel)
                        .foregroundColor(.white)
                }
                Spacer()
            }
            .padding(.vertical, SacredSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: SacredRadius.pill)
                    .fill(Color.sacredGold)
            )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 50)
        .disabled(!canSave || saving)
        .opacity((canSave && !saving) ? 1.0 : 0.45)
    }

    private var canSave: Bool {
        guard let shares = Double(sharesText), shares > 0 else { return false }
        guard let cost = Double(costText), cost > 0 else { return false }
        return true
    }

    private func save(ticker: String) async {
        localError = nil
        guard let shares = Double(sharesText), shares > 0 else {
            localError = "Enter a share count greater than 0."
            return
        }
        guard let cost = Double(costText), cost > 0 else {
            localError = "Enter a cost per share greater than 0."
            return
        }
        saving = true
        let ok = await vm.addPosition(ticker: ticker, shares: shares, costBasis: cost)
        saving = false
        if ok {
            onSaved()
            dismiss()
        }
    }
}

/// Symbol search — no NavigationStack of its own, so it composes cleanly
/// inside AddPositionView's stack. Debounced and backed by
/// `/api/wisecat/symbols/search`.
private struct TickerSearchSheetEmbedded: View {
    var excluded: Set<String>
    var onSelect: (String) -> Void

    @State private var query = ""
    @State private var results: [SymbolMatch] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SacredSpacing.m) {
                searchField
                resultList
            }
            .padding(.horizontal, SacredSpacing.m)
            .padding(.top, SacredSpacing.l)
            .padding(.bottom, SacredSpacing.tabBarSafe)
        }
    }

    private var searchField: some View {
        HStack(spacing: SacredSpacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.sacredMuted)

            TextField("Search a ticker (e.g. AAPL, Nvidia)", text: $query)
                .font(.sacredText)
                .foregroundColor(.sacredText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onChange(of: query) { _, newValue in
                    scheduleSearch(newValue)
                }

            if searching {
                ProgressView()
                    .scaleEffect(0.7)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.sacredMuted)
                }
            }
        }
        .padding(.horizontal, SacredSpacing.m)
        .padding(.vertical, SacredSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: SacredRadius.card)
                .fill(Color.sacredBgCard)
        )
    }

    @ViewBuilder
    private var resultList: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Search for a US-listed stock or ETF to add to your portfolio.")
                .font(.sacredText)
                .foregroundColor(.sacredMuted)
                .padding(.top, SacredSpacing.l)
        } else if results.isEmpty && !searching {
            Text("No US-listed symbols match \"\(query)\".")
                .font(.sacredText)
                .foregroundColor(.sacredMuted)
                .padding(.top, SacredSpacing.l)
        } else {
            VStack(spacing: SacredSpacing.xs) {
                ForEach(results) { match in
                    let already = excluded.contains(match.symbol.uppercased())
                    Button {
                        if !already { onSelect(match.symbol.uppercased()) }
                    } label: {
                        HStack(alignment: .center, spacing: SacredSpacing.s) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(match.symbol)
                                    .font(.sacredSubheading)
                                    .foregroundColor(.sacredText)
                                Text(match.description)
                                    .font(.sacredSmall)
                                    .foregroundColor(.sacredTextSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if already {
                                Text("Already added")
                                    .font(.sacredSmallSemibold)
                                    .foregroundColor(.sacredMuted)
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.sacredGold)
                            }
                        }
                        .padding(.horizontal, SacredSpacing.m)
                        .padding(.vertical, SacredSpacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: SacredRadius.card)
                                .fill(Color.sacredBgCard)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(already)
                }
            }
        }
    }

    private func scheduleSearch(_ raw: String) {
        searchTask?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            results = []
            searching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }

            await MainActor.run { self.searching = true }
            do {
                let hits = try await WiseCatAPI.searchSymbols(trimmed)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.results = hits
                    self.searching = false
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.results = []
                    self.searching = false
                }
            }
        }
    }
}
