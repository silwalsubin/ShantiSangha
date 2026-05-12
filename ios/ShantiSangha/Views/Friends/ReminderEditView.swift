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
    let onSave: (_ label: String, _ date: String, _ recurrence: ReminderRecurrence) async -> Void
    let onDelete: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var labelDraft: String = ""
    @State private var dateDraft: Date = Date()
    @State private var displayedMonth: Date = Date()
    @State private var recurrenceDraft: ReminderRecurrence = .yearly
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

    var body: some View {
        ScrollView {
            VStack(spacing: SacredSpacing.l) {
                labelSection
                dateSection
                recurrenceSection
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
        .onAppear { seed() }
        .confirmationDialog(
            "Delete this reminder?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancel", role: .cancel) {}
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
        }
        // Open the picker on the seeded date's month so the user sees
        // their saved date without having to navigate to it first.
        displayedMonth = dateDraft
    }

    private func save() async {
        let trimmed = labelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        saving = true
        defer { saving = false }
        await onSave(trimmed, formatISODate(dateDraft), recurrenceDraft)
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
