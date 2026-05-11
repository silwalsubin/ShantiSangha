import SwiftUI

/// Where the user enters/edits their real holdings. Hands control off to
/// PortfolioPlanView (pushed via NavigationLink) once they ask for the audit.
struct PortfolioInputView: View {
    @StateObject private var vm = PortfolioViewModel()
    @Environment(\.dismiss) private var dismiss

    /// In-flight edits — kept separate from `vm.positions` so the user can
    /// cancel without persisting. Each row is its own draft.
    @State private var drafts: [PositionDraft] = []
    @State private var cashText: String = ""
    @State private var showPlan = false
    @State private var showTickerSearch = false

    var body: some View {
        NavigationStack {
            ZStack {
                SacredBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: SacredSpacing.l) {
                        explanation
                        cashField
                        positionsList
                        addButton
                        if let err = vm.error {
                            Text(err)
                                .font(.sacredCaption)
                                .foregroundColor(.sacredRed)
                        }
                        generateButton
                    }
                    .padding(.horizontal, SacredSpacing.m)
                    .padding(.top, SacredSpacing.l)
                    .padding(.bottom, SacredSpacing.tabBarSafe)
                }
            }
            .navigationTitle("Your portfolio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.sacredGold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .foregroundColor(.sacredGold)
                        .disabled(vm.loading)
                }
            }
            .navigationDestination(isPresented: $showPlan) {
                PortfolioPlanView(plan: vm.plan, regenerating: vm.generatingPlan) {
                    await vm.generatePlan()
                }
            }
            .sheet(isPresented: $showTickerSearch) {
                TickerSearchSheet(excluded: Set(drafts.map { $0.ticker.uppercased() })) { picked in
                    var d = PositionDraft()
                    d.ticker = picked
                    drafts.append(d)
                }
            }
        }
        .task {
            await vm.loadPortfolio()
            self.drafts = vm.positions.map(PositionDraft.init)
            self.cashText = vm.cashBalance > 0 ? String(format: "%.2f", vm.cashBalance) : ""
        }
    }

    // MARK: subviews

    private var explanation: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                Text("Your starting point")
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
                Text("Add every stock you currently own — ticker, share count, and cost per share. The plan is generated against your 10 ratified rules.")
                    .font(.sacredText)
                    .foregroundColor(.sacredTextSecondary)
            }
            .padding(SacredSpacing.lux)
        }
    }

    private var cashField: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                Text("Un-invested cash")
                    .font(.sacredSmallSemibold)
                    .foregroundColor(.sacredTextSecondary)
                TextField("0.00", text: $cashText)
                    .font(.sacredHeading)
                    .foregroundColor(.sacredText)
                    .keyboardType(.decimalPad)
                    .onChange(of: cashText) { _, newValue in
                        vm.cashBalance = Double(newValue) ?? 0
                    }
            }
            .padding(SacredSpacing.lux)
        }
    }

    private var positionsList: some View {
        VStack(spacing: SacredSpacing.s) {
            if drafts.isEmpty {
                Text("No positions yet. Tap “Add position” below.")
                    .font(.sacredText)
                    .foregroundColor(.sacredMuted)
                    .padding(.top, SacredSpacing.s)
            } else {
                ForEach($drafts) { $draft in
                    PositionDraftRow(draft: $draft) {
                        if let idx = drafts.firstIndex(where: { $0.id == draft.id }) {
                            drafts.remove(at: idx)
                        }
                    }
                }
            }
        }
    }

    private var addButton: some View {
        Button {
            showTickerSearch = true
        } label: {
            HStack(spacing: SacredSpacing.s) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.sacredGold)
                Text("Add position")
                    .font(.sacredButtonLabel)
                    .foregroundColor(.sacredGold)
                Spacer()
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.sacredMuted)
            }
            .padding(.horizontal, SacredSpacing.m)
            .padding(.vertical, SacredSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SacredRadius.card)
                    .fill(Color.sacredBgCard)
            )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }

    private var generateButton: some View {
        Button {
            Task {
                await save()
                if vm.error == nil {
                    await vm.generatePlan()
                    if vm.plan != nil { showPlan = true }
                }
            }
        } label: {
            HStack {
                Spacer()
                if vm.generatingPlan {
                    ProgressView().tint(.white)
                } else {
                    Text("Generate plan")
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
        .disabled(drafts.isEmpty || vm.loading || vm.generatingPlan)
        .opacity((drafts.isEmpty || vm.loading || vm.generatingPlan) ? 0.45 : 1.0)
    }

    private func save() async {
        // Filter incomplete drafts. Any row missing ticker / shares / cost
        // is silently dropped — the input view enforces real data before
        // sending up.
        let clean: [SavePortfolioPosition] = drafts.compactMap { d in
            let t = d.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !t.isEmpty else { return nil }
            guard let shares = Double(d.shares), shares > 0 else { return nil }
            guard let cb = Double(d.costBasis), cb > 0 else { return nil }
            return SavePortfolioPosition(ticker: t, shares: shares, costBasis: cb)
        }
        await vm.savePortfolio(clean)
    }
}

// MARK: drafts

/// One row of the input form. Strings throughout so partial / mid-typing
/// values don't blow up; validated on save.
struct PositionDraft: Identifiable, Hashable {
    let id = UUID()
    var ticker: String = ""
    var shares: String = ""
    var costBasis: String = ""

    init() {}
    init(_ existing: PortfolioPosition) {
        self.ticker = existing.ticker
        self.shares = String(format: "%.2f", existing.shares)
        self.costBasis = String(format: "%.2f", existing.costBasis)
    }
}

private struct PositionDraftRow: View {
    @Binding var draft: PositionDraft
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: SacredSpacing.s) {
            VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                Text("Ticker")
                    .font(.sacredCaption)
                    .foregroundColor(.sacredMuted)
                Text(draft.ticker)
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
            }
            .frame(width: 80, alignment: .leading)

            VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                Text("Shares")
                    .font(.sacredCaption)
                    .foregroundColor(.sacredMuted)
                TextField("0", text: $draft.shares)
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
                    .keyboardType(.decimalPad)
            }

            VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                Text("Cost/share")
                    .font(.sacredCaption)
                    .foregroundColor(.sacredMuted)
                TextField("0.00", text: $draft.costBasis)
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
                    .keyboardType(.decimalPad)
            }

            Button(role: .destructive, action: onDelete) {
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
