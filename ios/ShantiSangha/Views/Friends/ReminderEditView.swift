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
    @State private var recurrenceDraft: ReminderRecurrence = .yearly
    @State private var saving = false
    @State private var deleting = false
    @State private var didSeed = false
    @State private var showDeleteConfirm = false

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
                DatePicker(
                    "",
                    selection: $dateDraft,
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .datePickerStyle(.graphical)
                .tint(.sacredGold)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
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
        case .new(let initialLabel, _):
            if let initialLabel, !initialLabel.isEmpty {
                labelDraft = initialLabel
            }
        case .edit(let reminder):
            labelDraft = reminder.label
            dateDraft = parseISODate(reminder.date) ?? Date()
            recurrenceDraft = reminder.recurrence
        }
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
    case new(initialLabel: String? = nil, connectionId: UUID? = nil)
    case edit(Reminder)

    var id: String {
        switch self {
        case .new(let label, let conn):
            return "new:\(label ?? "")\(conn?.uuidString ?? "")"
        case .edit(let reminder): return reminder.id.uuidString
        }
    }

    var isEditing: Bool {
        if case .edit = self { return true }
        return false
    }

    var initialLabel: String? {
        if case .new(let label, _) = self { return label }
        return nil
    }

    var connectionId: UUID? {
        if case .new(_, let id) = self { return id }
        if case .edit(let r) = self { return r.connectionId }
        return nil
    }
}
