import SwiftUI

/// Modal picker for a single ticker, backed by `/api/wisecat/symbols/search`.
/// Used by PortfolioInputView's "Add position" flow and any future spot
/// where we ask the user to pick a stock from a validated list rather than
/// type free-form.
struct TickerSearchSheet: View {
    /// Disallow these tickers (e.g. ones the user already has in their portfolio).
    var excluded: Set<String> = []
    /// Called when the user taps a result. Sheet dismisses automatically.
    var onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SymbolMatch] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                SacredBackground()
                    .ignoresSafeArea()

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
            .navigationTitle("Add a ticker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.sacredGold)
                }
            }
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
                        if !already {
                            onSelect(match.symbol.uppercased())
                            dismiss()
                        }
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
                                Image(systemName: "plus.circle.fill")
                                    .font(.sacredHeading)
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
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
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
