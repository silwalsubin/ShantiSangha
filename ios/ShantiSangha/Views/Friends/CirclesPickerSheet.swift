import SwiftUI

/// Sheet for adding a single circle to a connection. Shows the user's
/// existing circles (sorted by frequency) so the second-time-adding case
/// is one tap, and surfaces a "Create '<typed>'" row when nothing matches
/// so a brand-new circle is also one tap. Single-add by design — chips
/// are removed via the ✕ on each chip in the parent view, and the sheet
/// re-opens for the next add.
struct CirclesPickerSheet: View {
    /// Existing circles in use across the user's connections, with usage
    /// counts. Used both as autocomplete suggestions and to decide whether
    /// the typed text would create a new circle.
    let catalog: [(name: String, count: Int)]
    /// Circles already on the connection being edited — filtered out of
    /// the suggestion list so the user can't double-add.
    let alreadyAdded: Set<String>
    let onPick: (String) -> Void
    let onCancel: () -> Void

    @State private var query: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Divider().padding(.horizontal, SacredSpacing.m)

                ScrollView {
                    VStack(spacing: 0) {
                        if let createRow = newCircleRow {
                            createRow
                            if !filteredCatalog.isEmpty {
                                Divider().padding(.leading, 56)
                            }
                        }

                        ForEach(Array(filteredCatalog.enumerated()), id: \.element.name) { idx, item in
                            suggestionRow(item)
                            if idx < filteredCatalog.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }

                        if newCircleRow == nil && filteredCatalog.isEmpty {
                            emptyState
                        }
                    }
                }
            }
            .background(SacredBackground().ignoresSafeArea())
            .navigationTitle("Add to circles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                        .foregroundColor(.sacredMuted)
                }
            }
        }
        .onAppear { focused = true }
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
            TextField("Search or create…", text: $query)
                .font(.sacredText)
                .foregroundColor(.sacredText)
                .submitLabel(.done)
                .focused($focused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .onSubmit {
                    if let row = newCircleRowName {
                        onPick(row)
                    } else if let first = filteredCatalog.first {
                        onPick(first.name)
                    }
                }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.sacredMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SacredSpacing.m)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func suggestionRow(_ item: (name: String, count: Int)) -> some View {
        Button { onPick(item.name) } label: {
            HStack(spacing: 12) {
                Image(systemName: "circle.grid.2x2.fill")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredGold)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.sacredGold.opacity(0.12)))

                Text(item.name)
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredText)

                Spacer()

                Text(usageLabel(item.count))
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
            }
            .padding(.horizontal, SacredSpacing.m)
            .padding(.vertical, 14)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "Create '<typed>'" row when the trimmed query is non-empty and
    /// doesn't match any existing circle (case-insensitively). nil
    /// means: don't render the create row.
    @ViewBuilder
    private var newCircleRow: (some View)? {
        if let name = newCircleRowName {
            Button { onPick(name) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.sacredGold)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.sacredGold.opacity(0.12)))

                    Text("Create \u{201C}\(name)\u{201D}")
                        .font(.sacredTextSemibold)
                        .foregroundColor(.sacredText)

                    Spacer()
                }
                .padding(.horizontal, SacredSpacing.m)
                .padding(.vertical, 14)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 32)
            Text("Type to create your first circle")
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 32)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Logic

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredCatalog: [(name: String, count: Int)] {
        let q = trimmedQuery
        return catalog
            .filter { item in
                if alreadyAdded.contains(where: { $0.caseInsensitiveCompare(item.name) == .orderedSame }) {
                    return false
                }
                if q.isEmpty { return true }
                return item.name.localizedCaseInsensitiveContains(q)
            }
    }

    /// Returns the display name to put in the "Create '<typed>'" row, or
    /// nil if a create row shouldn't be shown (empty query, exact match,
    /// or already on the connection).
    private var newCircleRowName: String? {
        let q = trimmedQuery
        guard !q.isEmpty else { return nil }
        if alreadyAdded.contains(where: { $0.caseInsensitiveCompare(q) == .orderedSame }) {
            return nil
        }
        if catalog.contains(where: { $0.name.caseInsensitiveCompare(q) == .orderedSame }) {
            return nil
        }
        return q
    }

    private func usageLabel(_ count: Int) -> String {
        count == 1 ? "1 person" : "\(count) people"
    }
}
