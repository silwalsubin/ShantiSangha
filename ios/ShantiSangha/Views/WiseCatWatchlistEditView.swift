import SwiftUI

struct WiseCatWatchlistEditView: View {
    @ObservedObject var vm: WiseCatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [SymbolMatch] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var addingTicker: String?

    var body: some View {
        NavigationStack {
            ZStack {
                SacredBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: SacredSpacing.m) {
                        headerHero

                        searchField

                        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                            searchResults
                        } else {
                            currentWatchlist
                        }

                        if let err = vm.error {
                            Text(err)
                                .font(.sacredCaption)
                                .foregroundColor(.sacredRed)
                        }
                    }
                    .padding(.horizontal, SacredSpacing.m)
                    .padding(.top, SacredSpacing.l)
                    .padding(.bottom, SacredSpacing.tabBarSafe)
                }
            }
            .navigationTitle("Watchlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.sacredGold)
                }
            }
        }
    }

    private var headerHero: some View {
        Text("Watchlist")
            .font(.sacredTitle)
            .foregroundColor(.sacredText)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var searchResults: some View {
        VStack(spacing: SacredSpacing.xs) {
            if results.isEmpty && !searching {
                Text("No US-listed symbols match \"\(query)\".")
                    .font(.sacredText)
                    .foregroundColor(.sacredMuted)
                    .padding(.top, SacredSpacing.l)
            } else {
                ForEach(results) { match in
                    Button {
                        Task { await add(match.symbol) }
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
                            if alreadyOnList(match.symbol) {
                                Text("Added")
                                    .font(.sacredSmallSemibold)
                                    .foregroundColor(.sacredMuted)
                            } else if addingTicker == match.symbol {
                                ProgressView()
                                    .scaleEffect(0.8)
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
                    .disabled(alreadyOnList(match.symbol) || addingTicker != nil)
                }
            }
        }
    }

    @ViewBuilder
    private var currentWatchlist: some View {
        if vm.watchlist.isEmpty {
            Text("Search for a ticker above to start receiving daily reads.")
                .font(.sacredText)
                .foregroundColor(.sacredMuted)
                .padding(.top, SacredSpacing.l)
        } else {
            VStack(spacing: SacredSpacing.xs) {
                ForEach(vm.watchlist) { entry in
                    HStack {
                        Text(entry.ticker)
                            .font(.sacredSubheading)
                            .foregroundColor(.sacredText)
                        Spacer()
                        Button(role: .destructive) {
                            Task { await vm.remove(entry.ticker) }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.sacredGoldDark)
                        }
                        .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, SacredSpacing.m)
                    .padding(.vertical, SacredSpacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: SacredRadius.card)
                            .fill(Color.sacredBgCard)
                    )
                }
            }
        }
    }

    private func alreadyOnList(_ ticker: String) -> Bool {
        vm.watchlist.contains(where: { $0.ticker == ticker })
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
                if error.isCancellation {
                    await MainActor.run { self.searching = false }
                    return
                }
                await MainActor.run {
                    self.results = []
                    self.searching = false
                }
            }
        }
    }

    private func add(_ ticker: String) async {
        addingTicker = ticker
        defer { addingTicker = nil }
        await vm.add(ticker)
        // After a successful add, clear the search bar so they can find the next.
        if vm.error == nil {
            await MainActor.run {
                query = ""
                results = []
            }
        }
    }
}
