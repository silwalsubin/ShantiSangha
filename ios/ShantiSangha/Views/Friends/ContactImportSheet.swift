import SwiftUI

/// Review step for pulling a linked contact's details onto someone already in
/// the circle. Anything the profile is missing is checked and ready to go;
/// anything that would replace what's already there starts unchecked and says
/// what it would overwrite, so nothing you typed is lost by accident.
struct ContactImportSheet: View {
    struct Item: Identifiable, Equatable {
        enum Field: Hashable { case photo, phone, email, birthday }

        let id: Field
        let label: String
        /// What the contact card offers.
        let incoming: String
        /// What the profile holds today — nil when the field is empty, which
        /// is what makes this a fill rather than a replace.
        let existing: String?

        var replaces: Bool { existing != nil }
    }

    let contactName: String
    let items: [Item]
    let importing: Bool
    let onImport: (Set<Item.Field>) -> Void
    let onCancel: () -> Void

    @State private var selected: Set<Item.Field>

    init(
        contactName: String,
        items: [Item],
        importing: Bool,
        onImport: @escaping (Set<Item.Field>) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.contactName = contactName
        self.items = items
        self.importing = importing
        self.onImport = onImport
        self.onCancel = onCancel
        // Fills are on by default; replacements are a deliberate choice.
        _selected = State(initialValue: Set(items.filter { !$0.replaces }.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.l) {
            Text("From \(contactName)'s card")
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
                .padding(.horizontal, 4)

            SacredListCard {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 16) }
                        row(item)
                    }
                }
            }

            Button {
                onImport(selected)
            } label: {
                Text(selected.isEmpty ? "Nothing selected" : "Import")
                    .font(.sacredButtonLabel)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(LinearGradient.sacredGoldShinyVertical)
                    .clipShape(Capsule())
                    .opacity(selected.isEmpty || importing ? 0.5 : 1)
            }
            .disabled(selected.isEmpty || importing)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SacredSpacing.m)
        .padding(.top, SacredSpacing.s)
    }

    private func row(_ item: Item) -> some View {
        Button {
            if selected.contains(item.id) {
                selected.remove(item.id)
            } else {
                selected.insert(item.id)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.label)
                        .font(.sacredMicroBold)
                        .foregroundColor(.sacredLabel)
                    Text(item.incoming)
                        .font(.sacredText)
                        .foregroundColor(.sacredText)
                        .lineLimit(1)
                    if let existing = item.existing {
                        Text("Replaces \(existing)")
                            .font(.sacredMicro)
                            .foregroundColor(.sacredMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(selected.contains(item.id) ? .sacredGold : .sacredMuted.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
