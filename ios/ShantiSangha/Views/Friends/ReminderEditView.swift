import SwiftUI

/// Full-page add / edit reminder. Pushed onto the parent's NavigationStack
/// from Home (tap a row) and ConnectionDetailView (Important Dates).
///
/// The parent owns persistence; this view only collects the values and
/// calls back via `onSave`. `onDelete` is non-nil only for the edit path
/// so the destructive button stays out of the add flow. Both callbacks
/// dismiss the page (pop) when they succeed.
struct ReminderEditView: View {
    let target: ReminderEditTarget
    /// Save callback. `collaboratorUserIds` is the full desired set of
    /// friend user IDs the owner wants on this reminder — pass nil from
    /// callsites that don't surface the sharing UI to leave it
    /// untouched. The picker sends an empty set to clear all sharing.
    let onSave: (_ label: String,
                 _ date: String,
                 _ recurrence: ReminderRecurrence,
                 _ collaboratorUserIds: [UUID]?) async -> Void
    let onDelete: (() async -> Void)?
    /// Auto-save hook for collaborator changes in edit mode. Non-nil
    /// only when the reminder already exists on the server (so we can
    /// PATCH it). The picker and per-row remove call this immediately
    /// instead of waiting for the user to tap Save — collaboration
    /// changes are high-stakes (people see / lose access, push fires)
    /// so they commit atomically. Returns the updated reminder so the
    /// view can refresh its local copy with the server-resolved names.
    let onCollaboratorsChanged: ((_ collaboratorUserIds: [UUID]) async -> Reminder?)?

    @Environment(\.dismiss) private var dismiss

    @State private var labelDraft: String = ""
    @State private var dateDraft: Date = Date()
    @State private var displayedMonth: Date = Date()
    @State private var recurrenceDraft: ReminderRecurrence = .yearly
    /// Sharing draft. Lives only on this screen — committed via `onSave`
    /// when the user taps the toolbar action.
    @State private var collaboratorsDraft: [ReminderCollaboratorSummary] = []
    @State private var collaboratorsDirty = false
    @State private var collaboratorsSaving = false
    @State private var showSharePicker = false
    @State private var friends: [FriendSummary] = []
    @State private var friendsLoading = false
    @State private var saving = false
    @State private var deleting = false
    @State private var didSeed = false
    @State private var showDeleteConfirm = false
    /// The full month grid is heavy visually — keep it collapsed by
    /// default so the edit page reads as a short form. Tapping the date
    /// summary expands it.
    @State private var dateExpanded = false

    private var canSave: Bool {
        !labelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Is this reminder editable by the viewer as the owner? Collaborators
    /// can edit the label / date / recurrence but can't manage the
    /// collaborator set itself.
    private var viewerIsOwner: Bool {
        switch target {
        case .new: return true
        case .edit(let reminder): return !reminder.isSharedWithMe
        }
    }

    /// Display name to show in the "Shared by …" header on a recipient's
    /// view. Nil for owner-side views and for the add flow.
    private var sharedByLabel: String? {
        if case .edit(let reminder) = target,
           reminder.isSharedWithMe,
           let name = reminder.ownerDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SacredSpacing.l) {
                if let sharedByLabel {
                    sharedByBanner(name: sharedByLabel)
                }
                labelSection
                dateSection
                recurrenceSection
                if viewerIsOwner {
                    sharedWithSection
                }
                if onDelete != nil {
                    deleteSection
                }
            }
            .padding(.horizontal, SacredSpacing.m)
            .padding(.vertical, SacredSpacing.l)
        }
        .background(SacredBackground().ignoresSafeArea())
        .navigationTitle(target.isEditing ? "Edit reminder" : "Add reminder")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(target.isEditing ? "Save" : "Add") {
                    Task { await save() }
                }
                .foregroundColor(canSave ? .sacredGold : .sacredMutedLight)
                .disabled(!canSave || saving || deleting)
            }
        }
        .onAppear {
            seed()
            if viewerIsOwner { Task { await loadFriendsIfNeeded() } }
        }
        .confirmationDialog(
            sharedConfirmCopy,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showSharePicker) {
            CollaboratorPickerSheet(
                friends: friends,
                initialSelection: Set(collaboratorsDraft.map { $0.userId }),
                onDone: { selected in
                    applySelection(selected)
                    showSharePicker = false
                },
                onCancel: { showSharePicker = false })
        }
    }

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("LABEL")
            SacredListCard {
                TextField("Birthday, anniversary…", text: $labelDraft)
                    .font(.sacredText)
                    .foregroundColor(.sacredText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.sentences)
            }
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("DATE")
            SacredListCard {
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            dateExpanded.toggle()
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            Text(collapsedDateLabel(dateDraft))
                                .font(.sacredText)
                                .foregroundColor(.sacredGold)
                            Spacer()
                            Image(systemName: dateExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.sacredGold.opacity(0.55))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if dateExpanded {
                        Divider().padding(.horizontal, 12)
                        MonthCalendarPicker(
                            displayedMonth: $displayedMonth,
                            selectedDate: $dateDraft)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                    }
                }
            }
        }
    }

    /// "Saturday, May 16, 1987" — full date string used in the collapsed
    /// row so the user sees what's saved without expanding the grid.
    private func collapsedDateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f.string(from: date)
    }

    private var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("REPEATS")
            SacredListCard {
                VStack(spacing: 0) {
                    recurrenceRow(title: "Every year", value: .yearly)
                    Divider().padding(.leading, 16)
                    recurrenceRow(title: "One-time", value: .none)
                }
            }
        }
    }

    private func recurrenceRow(
        title: String,
        value: ReminderRecurrence
    ) -> some View {
        Button {
            recurrenceDraft = value
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.sacredText)
                    .foregroundColor(.sacredText)
                Spacer(minLength: 0)
                if recurrenceDraft == value {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.sacredGold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Owner-only collaborator manager. The header doubles as a preview:
    /// it shows the current collaborators' avatars overlapped (or an
    /// "Add collaborators" affordance when empty) with a chevron to
    /// open the multi-select sheet. Each picked person also gets a row
    /// below with an ✕ for one-tap removal. Add and remove both
    /// auto-save in edit mode so the user doesn't have to tap Save.
    private var sharedWithSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("COLLABORATORS")
            SacredListCard {
                VStack(spacing: 0) {
                    Button {
                        showSharePicker = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 12) {
                            if collaboratorsDraft.isEmpty {
                                Image(systemName: "person.2.fill")
                                    .font(.sacredSmall)
                                    .foregroundColor(.sacredGold)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(Color.sacredGold.opacity(0.12)))

                                Text("Add collaborators")
                                    .font(.sacredText)
                                    .foregroundColor(.sacredText)
                            } else {
                                collaboratorHeaderStack
                            }

                            Spacer()

                            if friendsLoading || collaboratorsSaving {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.sacredMuted)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.sacredMuted.opacity(0.55))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(collaboratorsDraft.isEmpty
                 ? "Private to you. Add a friend to share it."
                 : "They can view, edit, complete, and delete this reminder.")
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
                .padding(.horizontal, 4)
        }
    }

    /// Overlapping-avatar preview used inside the section header. Same
    /// visual idiom as the row's pip — up to three 24pt avatars plus a
    /// "+N" dot when there are more.
    @ViewBuilder
    private var collaboratorHeaderStack: some View {
        let visible = Array(collaboratorsDraft.prefix(3))
        let overflow = collaboratorsDraft.count - visible.count
        HStack(spacing: -10) {
            ForEach(visible, id: \.userId) { c in
                ProfileAvatarImage(rawUrl: c.avatarUrl, size: 24, borderWidth: 1.5)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.sacredText)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.sacredGold.opacity(0.20)))
                    .overlay(Circle().stroke(Color.sacredBgCard, lineWidth: 1.5))
            }
        }
    }

    /// "Shared by Alice" banner shown on the recipient's view of a
    /// reminder. Communicates that this isn't your own private row.
    private func sharedByBanner(name: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.sacredSmall)
                .foregroundColor(.sacredGold)
            Text("Shared by \(name)")
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredText)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.sacredGold.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.sacredGold.opacity(0.25), lineWidth: 1)))
    }

    private var deleteSection: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            HStack {
                if deleting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.sacredRed)
                }
                Text(deleting ? "Deleting…" : "Delete reminder")
                    .font(.sacredText)
                    .foregroundColor(.sacredRed)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.sacredRed.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(saving || deleting)
        .padding(.top, SacredSpacing.l)
    }

    /// Either "Delete this reminder?" or, when shared, an explicit copy
    /// that telegraphs cascade — the row goes away for the people it's
    /// shared with too.
    private var sharedConfirmCopy: String {
        let shared: Bool = {
            if !collaboratorsDraft.isEmpty { return true }
            if case .edit(let reminder) = target, reminder.isSharedWithMe { return true }
            return false
        }()
        return shared
            ? "Delete for everyone it's shared with?"
            : "Delete this reminder?"
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.sacredSectionLabel)
            .foregroundColor(.sacredLabel)
            .padding(.horizontal, 4)
    }

    private func seed() {
        guard !didSeed else { return }
        didSeed = true
        switch target {
        case .new(let initialLabel, let initialDate, _):
            if let initialLabel, !initialLabel.isEmpty {
                labelDraft = initialLabel
            }
            if let initialDate {
                dateDraft = initialDate
            }
        case .edit(let reminder):
            labelDraft = reminder.label
            dateDraft = parseISODate(reminder.date) ?? Date()
            recurrenceDraft = reminder.recurrence
            collaboratorsDraft = reminder.collaborators
        }
        // Open the picker on the seeded date's month so the user sees
        // their saved date without having to navigate to it first.
        displayedMonth = dateDraft
    }

    /// Diff the picker's returned ID set against the current draft and
    /// rebuild `collaboratorsDraft` so removed rows drop and added rows
    /// land with a placeholder display name (real name comes back from
    /// the server on save).
    private func applySelection(_ selected: Set<UUID>) {
        let before = collaboratorsDraft
        let kept = collaboratorsDraft.filter { selected.contains($0.userId) }
        let existingIds = Set(kept.map { $0.userId })
        let added: [ReminderCollaboratorSummary] = selected
            .subtracting(existingIds)
            .compactMap { id in
                if let friend = friends.first(where: { $0.friendUserId == id }) {
                    return ReminderCollaboratorSummary(
                        userId: id,
                        displayName: friend.displayLabel,
                        avatarUrl: friend.avatarUrl)
                }
                return nil
            }
        let next = (kept + added).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let changed = next.map(\.userId) != collaboratorsDraft.map(\.userId)
        if changed {
            collaboratorsDirty = true
        }
        collaboratorsDraft = next
        if changed {
            Task { await autoSaveCollaborators(previous: before) }
        }
    }

    /// Commits the current collaborator draft to the server immediately
    /// (edit mode only — the `.new` path keeps staging until Save). On
    /// success we re-seed the local list from the server response so
    /// freshly-added rows pick up the authoritative display name /
    /// avatar (the picker only knows what `FriendsAPI.listFriends`
    /// returns). On failure we revert and leave `Save` as the fallback
    /// path so the user can still recover.
    private func autoSaveCollaborators(previous: [ReminderCollaboratorSummary]) async {
        guard let onCollaboratorsChanged else { return }
        collaboratorsSaving = true
        defer { collaboratorsSaving = false }
        let ids = collaboratorsDraft.map(\.userId)
        if let updated = await onCollaboratorsChanged(ids) {
            collaboratorsDraft = updated.collaborators
            // Server is now the source of truth — Save no longer needs
            // to re-send the collaborator field.
            collaboratorsDirty = false
        } else {
            collaboratorsDraft = previous
            AppLogger.shared.error("ReminderEdit", "Auto-save collaborators failed; reverted local set")
        }
    }

    private func loadFriendsIfNeeded() async {
        guard friends.isEmpty, !friendsLoading else { return }
        friendsLoading = true
        defer { friendsLoading = false }
        do {
            friends = try await FriendsAPI.listFriends()
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("ReminderEdit", "Failed to load friends: \(error)")
            }
        }
    }

    private func save() async {
        let trimmed = labelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        saving = true
        defer { saving = false }
        // Only forward collaborators when the viewer is the owner AND
        // they actually touched the set. Non-owners must never send
        // this field — the server returns 403 if they do.
        let collaboratorIds: [UUID]? = (viewerIsOwner && collaboratorsDirty)
            ? collaboratorsDraft.map(\.userId)
            : nil
        await onSave(trimmed, formatISODate(dateDraft), recurrenceDraft, collaboratorIds)
        dismiss()
    }

    private func delete() async {
        guard let onDelete else { return }
        deleting = true
        defer { deleting = false }
        await onDelete()
        dismiss()
    }

    // Parse / format in the user's local timezone so the DatePicker (which
    // operates in local time) round-trips the same calendar day.
    private func parseISODate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }

    private func formatISODate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}

/// Navigation target for the add/edit-reminder flow. `.new()` opens an
/// empty form; `.new(initialLabel:)` pre-fills the label so empty-state
/// preset rows can hand the user a one-tap path; `.edit(reminder)`
/// pre-fills the whole row and offers a destructive "Delete" action.
enum ReminderEditTarget: Identifiable, Hashable {
    case new(initialLabel: String? = nil, initialDate: Date? = nil, connectionId: UUID? = nil)
    case edit(Reminder)

    var id: String {
        switch self {
        case .new(let label, let date, let conn):
            let dateBit = date.map { "\(Int($0.timeIntervalSinceReferenceDate))" } ?? ""
            return "new:\(label ?? "")|\(dateBit)|\(conn?.uuidString ?? "")"
        case .edit(let reminder): return reminder.id.uuidString
        }
    }

    var isEditing: Bool {
        if case .edit = self { return true }
        return false
    }

    var initialLabel: String? {
        if case .new(let label, _, _) = self { return label }
        return nil
    }

    var initialDate: Date? {
        if case .new(_, let date, _) = self { return date }
        return nil
    }

    var connectionId: UUID? {
        if case .new(_, _, let id) = self { return id }
        if case .edit(let r) = self { return r.connectionId }
        return nil
    }
}
