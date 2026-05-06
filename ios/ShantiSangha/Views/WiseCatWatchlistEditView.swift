import SwiftUI

struct WiseCatWatchlistEditView: View {
    @ObservedObject var vm: WiseCatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newTicker = ""

    var body: some View {
        NavigationStack {
            ZStack {
                SacredBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: SacredSpacing.m) {
                        addRow

                        if vm.watchlist.isEmpty {
                            Text("Add tickers above to start receiving daily reads.")
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
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.sacredGold)
                }
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: SacredSpacing.s) {
            TextField("Add ticker (e.g. AAPL)", text: $newTicker)
                .font(.sacredText)
                .foregroundColor(.sacredText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, SacredSpacing.m)
                .padding(.vertical, SacredSpacing.s)
                .background(
                    RoundedRectangle(cornerRadius: SacredRadius.card)
                        .fill(Color.sacredBgCard)
                )
                .onSubmit { submit() }

            Button {
                submit()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.sacredHeading)
                    .foregroundColor(.sacredGold)
            }
            .frame(width: 44, height: 44)
            .disabled(newTicker.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func submit() {
        let cleaned = newTicker.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cleaned.isEmpty else { return }
        Task {
            await vm.add(cleaned)
            await MainActor.run { newTicker = "" }
        }
    }
}
