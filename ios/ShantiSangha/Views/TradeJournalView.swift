import SwiftUI

/// Rule 8 surface — daily check + journal. The user logs each entry,
/// exit, trim, or note so the weekly review has source material.
/// Reached from the slider icon in the Stocks tab toolbar.
struct TradeJournalView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [TradeJournalEntry] = []
    @State private var loading = true
    @State private var error: String?

    @State private var showingAdd = false

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let fallbackFormatter: ISO8601DateFormatter = ISO8601DateFormatter()

    var body: some View {
        NavigationStack {
            ZStack {
                SacredBackground()
                    .ignoresSafeArea()

                if loading && entries.isEmpty {
                    ProgressView().tint(.sacredGold)
                } else if entries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.sacredGold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.sacredGold)
                    }
                }
            }
            .sheet(isPresented: $showingAdd, onDismiss: { Task { await load() } }) {
                AddJournalEntrySheet()
            }
        }
        .task { await load() }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SacredSpacing.m) {
                preamble
                ForEach(entries) { e in
                    LuxCard {
                        entryRow(e)
                    }
                }
            }
            .padding(.horizontal, SacredSpacing.m)
            .padding(.top, SacredSpacing.l)
            .padding(.bottom, SacredSpacing.tabBarSafe)
        }
    }

    private var preamble: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                Text("Daily check & journal")
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
                Text("One line per entry, exit, or note. Reviewed weekly. The discipline isn't in the rules — it's in the writing.")
                    .font(.sacredText)
                    .foregroundColor(.sacredTextSecondary)
            }
            .padding(SacredSpacing.lux)
        }
    }

    private var emptyState: some View {
        VStack(spacing: SacredSpacing.m) {
            Text("Nothing logged yet.")
                .font(.sacredSubheading)
                .foregroundColor(.sacredText)
            Text("Log every entry and exit with the reason. The weekly review depends on it.")
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)
                .multilineTextAlignment(.center)
            Button {
                showingAdd = true
            } label: {
                Text("Add first entry")
                    .font(.sacredButtonLabel)
                    .foregroundColor(.sacredGold)
            }
        }
        .padding(SacredSpacing.l)
    }

    @ViewBuilder
    private func entryRow(_ e: TradeJournalEntry) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            HStack {
                Text(e.ticker)
                    .font(.sacredHeading)
                    .foregroundColor(.sacredText)
                kindBadge(e.kind)
                Spacer()
                Text(formattedDate(e.createdAt))
                    .font(.sacredCaption)
                    .foregroundColor(.sacredMuted)
            }
            HStack(spacing: SacredSpacing.s) {
                if let price = e.price {
                    Text(String(format: "$%.2f", price))
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.sacredTextSecondary)
                }
                if let shares = e.shares {
                    Text(String(format: "%.4g sh", shares))
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.sacredTextSecondary)
                }
            }
            if let reason = e.reason, !reason.isEmpty {
                Text(reason)
                    .font(.sacredText)
                    .foregroundColor(.sacredText)
            }
        }
        .padding(SacredSpacing.lux)
        .contextMenu {
            Button(role: .destructive) {
                Task { await delete(e) }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func kindBadge(_ kind: String) -> some View {
        let color: Color = {
            switch kind {
            case "Entry": return .sacredGreen
            case "Exit":  return .sacredRed
            case "Trim":  return .sacredGold
            case "AddOn": return .sacredGreenDark
            default:      return .sacredMuted
            }
        }()
        return Text(kind.uppercased())
            .font(.sacredCaption)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(4)
    }

    private func formattedDate(_ iso: String) -> String {
        let date = isoFormatter.date(from: iso) ?? fallbackFormatter.date(from: iso)
        guard let date else { return iso }
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        return f.string(from: date)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            entries = try await WiseCatAPI.listJournal()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ e: TradeJournalEntry) async {
        do {
            try await WiseCatAPI.deleteJournalEntry(e.id)
            entries.removeAll { $0.id == e.id }
        } catch {
            self.error = "Delete failed: \(error.localizedDescription)"
        }
    }
}

/// Add-entry sheet — minimal form.
private struct AddJournalEntrySheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var ticker = ""
    @State private var kind = "Entry"
    @State private var priceText = ""
    @State private var sharesText = ""
    @State private var reason = ""
    @State private var saving = false
    @State private var error: String?

    private let kinds = ["Entry", "Exit", "Trim", "AddOn", "Note"]

    var body: some View {
        NavigationStack {
            ZStack {
                SacredBackground()
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: SacredSpacing.l) {
                        LuxCard {
                            VStack(alignment: .leading, spacing: SacredSpacing.m) {
                                field("Ticker", text: $ticker, keyboard: .asciiCapable)
                                    .textInputAutocapitalization(.characters)
                                VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                                    Text("Kind")
                                        .font(.sacredSmallSemibold)
                                        .foregroundColor(.sacredTextSecondary)
                                    Picker("Kind", selection: $kind) {
                                        ForEach(kinds, id: \.self) { Text($0).tag($0) }
                                    }
                                    .pickerStyle(.segmented)
                                }
                                field("Price (optional)", text: $priceText, keyboard: .decimalPad)
                                field("Shares (optional)", text: $sharesText, keyboard: .decimalPad)
                                VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                                    Text("Reason")
                                        .font(.sacredSmallSemibold)
                                        .foregroundColor(.sacredTextSecondary)
                                    TextEditor(text: $reason)
                                        .font(.sacredText)
                                        .frame(minHeight: 80)
                                        .scrollContentBackground(.hidden)
                                        .background(Color.sacredBgCard.opacity(0.4))
                                        .cornerRadius(6)
                                    Text("Why are you doing this? One line is enough.")
                                        .font(.sacredCaption)
                                        .foregroundColor(.sacredMuted)
                                }
                                if let err = error {
                                    Text(err)
                                        .font(.sacredCaption)
                                        .foregroundColor(.sacredRed)
                                }
                            }
                            .padding(SacredSpacing.lux)
                        }
                    }
                    .padding(.horizontal, SacredSpacing.m)
                    .padding(.top, SacredSpacing.l)
                }
            }
            .navigationTitle("Log entry")
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
                        if saving { ProgressView().tint(.sacredGold) }
                        else { Text("Save").foregroundColor(.sacredGold) }
                    }
                    .disabled(saving || ticker.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
            Text(label)
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredTextSecondary)
            TextField("", text: text)
                .font(.sacredText)
                .foregroundColor(.sacredText)
                .keyboardType(keyboard)
                .padding(SacredSpacing.xs)
                .background(Color.sacredBgCard.opacity(0.4))
                .cornerRadius(6)
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let req = CreateJournalEntryRequest(
            ticker: ticker.trimmingCharacters(in: .whitespaces),
            kind: kind,
            price: Double(priceText),
            shares: Double(sharesText),
            reason: reason.isEmpty ? nil : reason
        )
        do {
            _ = try await WiseCatAPI.addJournalEntry(req)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
