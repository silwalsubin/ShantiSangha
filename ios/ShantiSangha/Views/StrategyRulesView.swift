import SwiftUI

/// Editor for the user's tunable rule constants (Rule 1, 2, 3, 4, 10, 11).
/// PUTs to /api/wisecat/strategy/settings on save. Defaults are seeded
/// on the server (Mode D active trader); first GET creates the row.
struct StrategyRulesView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var settings: StrategySettings?
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    // Editable string buffers so partial input doesn't blow up.
    @State private var stopLossText = ""
    @State private var takeProfitText = ""
    @State private var entryThresholdText = ""
    @State private var positionCapText = ""
    @State private var cooldownText = ""
    @State private var minSectorsText = ""
    @State private var sellSignalText = ""
    @State private var horizon = "1W"

    @State private var backtest: StrategyBacktestResult?
    @State private var backtesting = false
    @State private var backtestError: String?

    private let horizons = ["1W", "1M", "1Y"]

    var body: some View {
        NavigationStack {
            ZStack {
                SacredBackground()
                    .ignoresSafeArea()

                if loading {
                    ProgressView().tint(.sacredGold)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: SacredSpacing.l) {
                            preamble
                            exitsCard
                            entryCard
                            sizingCard
                            backtestCard
                            if let err = error {
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
            }
            .navigationTitle("Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.sacredGold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving {
                            ProgressView().tint(.sacredGold)
                        } else {
                            Text("Save")
                                .foregroundColor(.sacredGold)
                        }
                    }
                    .disabled(saving || loading)
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Cards

    private var preamble: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                Text("Your rules, your numbers")
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
                Text("These tune the 10 rules behind the plan. Changes apply on the next plan generation. The defaults are the active-trader profile (-7% stop, +10% TP, 1W entry signal at p_buy ≥ 0.60).")
                    .font(.sacredText)
                    .foregroundColor(.sacredTextSecondary)
            }
            .padding(SacredSpacing.lux)
        }
    }

    private var exitsCard: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.m) {
                sectionTitle("Exits", subtitle: "Rule 3 (stop), Rule 11 (target), momentum reversal")
                percentField(label: "Stop-loss (% from cost)",
                             help: "When a position is down this much, exit. Default -7%.",
                             text: $stopLossText)
                percentField(label: "Take-profit (% from cost)",
                             help: "When a position is up this much, cash out. Default +10%.",
                             text: $takeProfitText)
                probField(label: "Sell on p_sell ≥ (0.40–0.95)",
                          help: "Exit when the model flips bearish at the entry horizon. Default 0.55. Lower = exit earlier on reversal.",
                          text: $sellSignalText)
            }
            .padding(SacredSpacing.lux)
        }
    }

    private var entryCard: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.m) {
                sectionTitle("Entries", subtitle: "Rule 10")
                VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                    Text("Signal horizon")
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.sacredTextSecondary)
                    Picker("Horizon", selection: $horizon) {
                        ForEach(horizons, id: \.self) { h in
                            Text(h).tag(h)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Active traders typically use 1W. Long-term holders use 1M or 1Y.")
                        .font(.sacredCaption)
                        .foregroundColor(.sacredMuted)
                }
                probField(label: "Min p_buy to enter (0.50–0.95)",
                          help: "How confident the model must be. Default 0.60 at 1W.",
                          text: $entryThresholdText)
                intField(label: "Cooldown after stop (days)",
                         help: "Wait this many days after a stop before re-entering the same ticker. Default 5.",
                         text: $cooldownText)
            }
            .padding(SacredSpacing.lux)
        }
    }

    private var backtestCard: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.m) {
                sectionTitle("Preview envelope", subtitle: "Coarse estimate from the 2026-05-10 basket backtest")
                if let r = backtest {
                    HStack(spacing: SacredSpacing.l) {
                        statBlock(label: "Return / yr",
                                  value: String(format: "%+.1f%%", r.annualizedReturnPct * 100),
                                  tint: r.annualizedReturnPct >= 0 ? .sacredGreen : .sacredRed)
                        statBlock(label: "Max DD",
                                  value: String(format: "%+.1f%%", r.maxDrawdownPct * 100),
                                  tint: .sacredRed)
                        statBlock(label: "Win rate",
                                  value: String(format: "%.0f%%", r.winRatePct * 100),
                                  tint: .sacredText)
                    }
                    Text(r.notes)
                        .font(.sacredCaption)
                        .foregroundColor(.sacredMuted)
                } else {
                    Text("Tap to see a rough envelope. The honest backtest still runs offline in `python -m wisecat.strategy_sim` — this is a directional sanity check before saving.")
                        .font(.sacredText)
                        .foregroundColor(.sacredTextSecondary)
                }
                if let err = backtestError {
                    Text(err)
                        .font(.sacredCaption)
                        .foregroundColor(.sacredRed)
                }
                Button {
                    Task { await runBacktest() }
                } label: {
                    HStack {
                        if backtesting { ProgressView().tint(.sacredGold) }
                        Text(backtest == nil ? "Preview backtest envelope" : "Refresh")
                            .font(.sacredButtonLabel)
                            .foregroundColor(.sacredGold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SacredSpacing.xs)
                }
                .disabled(backtesting)
            }
            .padding(SacredSpacing.lux)
        }
    }

    private func statBlock(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.sacredCaption)
                .foregroundColor(.sacredMuted)
            Text(value)
                .font(.sacredSubheading)
                .foregroundColor(tint)
        }
    }

    private func runBacktest() async {
        backtesting = true
        defer { backtesting = false }
        do {
            // Save current edits first so the backend sees the live constants.
            await save(dismissOnSuccess: false)
            backtest = try await WiseCatAPI.runStrategyBacktest()
            backtestError = nil
        } catch {
            backtestError = error.localizedDescription
        }
    }

    private var sizingCard: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.m) {
                sectionTitle("Sizing & diversification", subtitle: "Rules 1 & 2")
                percentField(label: "Max per position (% of portfolio)",
                             help: "Concentration cap. Default 10%.",
                             text: $positionCapText)
                intField(label: "Min sectors required",
                         help: "Coverage target. The basket has 10 sectors; default 8 keeps the spread.",
                         text: $minSectorsText)
            }
            .padding(SacredSpacing.lux)
        }
    }

    // MARK: - Field components

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.sacredSubheading)
                .foregroundColor(.sacredText)
            Text(subtitle)
                .font(.sacredCaption)
                .foregroundColor(.sacredMuted)
        }
    }

    private func percentField(label: String, help: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
            Text(label)
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredTextSecondary)
            HStack(spacing: SacredSpacing.xs) {
                TextField("0", text: text)
                    .font(.sacredHeading)
                    .foregroundColor(.sacredText)
                    .keyboardType(.decimalPad)
                Text("%")
                    .font(.sacredText)
                    .foregroundColor(.sacredMuted)
            }
            Text(help)
                .font(.sacredCaption)
                .foregroundColor(.sacredMuted)
        }
    }

    private func probField(label: String, help: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
            Text(label)
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredTextSecondary)
            TextField("0.60", text: text)
                .font(.sacredHeading)
                .foregroundColor(.sacredText)
                .keyboardType(.decimalPad)
            Text(help)
                .font(.sacredCaption)
                .foregroundColor(.sacredMuted)
        }
    }

    private func intField(label: String, help: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
            Text(label)
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredTextSecondary)
            TextField("0", text: text)
                .font(.sacredHeading)
                .foregroundColor(.sacredText)
                .keyboardType(.numberPad)
            Text(help)
                .font(.sacredCaption)
                .foregroundColor(.sacredMuted)
        }
    }

    // MARK: - I/O

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let s = try await WiseCatAPI.getStrategySettings()
            self.settings = s
            self.stopLossText = String(format: "%.0f", s.stopLossPct * 100)
            self.takeProfitText = String(format: "%.0f", s.takeProfitPct * 100)
            self.entryThresholdText = String(format: "%.2f", s.entryThresholdPBuy)
            self.positionCapText = String(format: "%.0f", s.positionCapPct * 100)
            self.cooldownText = String(s.cooldownDays)
            self.minSectorsText = String(s.minSectors)
            self.sellSignalText = String(format: "%.2f", s.sellSignalPSell)
            self.horizon = s.entryHorizon
            self.error = nil
        } catch {
            self.error = "Could not load rules: \(error.localizedDescription)"
        }
    }

    private func save(dismissOnSuccess: Bool = true) async {
        saving = true
        defer { saving = false }
        // Percent fields are entered as 0–100; the API expects 0.00–1.00.
        let stop = Double(stopLossText).map { $0 / 100 }
        let tp = Double(takeProfitText).map { $0 / 100 }
        let cap = Double(positionCapText).map { $0 / 100 }
        let threshold = Double(entryThresholdText)
        let cooldown = Int(cooldownText)
        let minSec = Int(minSectorsText)
        let sellSignal = Double(sellSignalText)

        let req = UpdateStrategySettingsRequest(
            stopLossPct: stop,
            takeProfitPct: tp,
            entryThresholdPBuy: threshold,
            entryHorizon: horizon,
            cooldownDays: cooldown,
            positionCapPct: cap,
            minSectors: minSec,
            sellSignalPSell: sellSignal
        )

        do {
            self.settings = try await WiseCatAPI.updateStrategySettings(req)
            self.error = nil
            if dismissOnSuccess { dismiss() }
        } catch {
            self.error = "Save failed: \(error.localizedDescription)"
        }
    }
}
