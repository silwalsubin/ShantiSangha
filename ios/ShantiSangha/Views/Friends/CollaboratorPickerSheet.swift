import SwiftUI

/// Multi-select sheet listing the viewer's accepted friends. Used from
/// `ReminderEditView` to add or remove collaborators on a reminder.
/// Mirrors the visual language of `CirclesPickerSheet` (search field on
/// top, avatar-fronted rows below) but with a checkmark per row and a
/// "Done" toolbar that commits the diff back to the parent.
struct CollaboratorPickerSheet: View {
    /// The viewer's current accepted friends. Loaded by the parent and
    /// passed in so this sheet doesn't have to manage its own networking.
    let friends: [FriendSummary]
    /// Friend user IDs already selected on the reminder. The sheet
    /// seeds its local selection from this set; the parent receives the
    /// final set via `onDone`.
    let initialSelection: Set<UUID>
    let onDone: (Set<UUID>) -> Void
    let onCancel: () -> Void

    @State private var selection: Set<UUID> = []
    @State private var query: String = ""
    @State private var didSeed = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Divider().padding(.horizontal, SacredSpacing.m)

                if filteredFriends.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredFriends.enumerated()), id: \.element.friendUserId) { idx, friend in
                                friendRow(friend)
                                if idx < filteredFriends.count - 1 {
                                    Divider().padding(.leading, 56)
                                }
                            }
                        }
                    }
                }
            }
            .background(SacredBackground().ignoresSafeArea())
            .navigationTitle("Share reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                        .foregroundColor(.sacredMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone(selection) }
                        .foregroundColor(.sacredGold)
                }
            }
        }
        .onAppear {
            if !didSeed {
                didSeed = true
                selection = initialSelection
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
            TextField("Search friends", text: $query)
                .typingHaptics(for: query)
                .font(.sacredText)
                .foregroundColor(.sacredText)
                .submitLabel(.done)
                .focused($focused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
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
    private func friendRow(_ friend: FriendSummary) -> some View {
        let isOn = selection.contains(friend.friendUserId)
        Button {
            if isOn { selection.remove(friend.friendUserId) }
            else { selection.insert(friend.friendUserId) }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                ProfileAvatarImage(rawUrl: friend.avatarUrl, size: 36, borderWidth: 1)

                Text(friend.displayLabel)
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredText)
                    .lineLimit(1)

                Spacer()

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(isOn ? .sacredGold : .sacredMuted.opacity(0.55))
            }
            .padding(.horizontal, SacredSpacing.m)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 40)
            Text(query.isEmpty
                 ? "Add friends in your Circles tab to share reminders with them."
                 : "No friends match \u{201C}\(query)\u{201D}")
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SacredSpacing.l)
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }

    private var filteredFriends: [FriendSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return friends.sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
        }
        return friends
            .filter { $0.displayLabel.localizedCaseInsensitiveContains(q) }
            .sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
    }
}
