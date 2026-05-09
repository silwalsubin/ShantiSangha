import SwiftUI

/// Add / edit a single "important date" on a Connection — birthday,
/// anniversary, day-we-met, etc. Free-form label paired with a date
/// picker and a recurrence toggle (annual vs one-time).
///
/// The parent owns persistence; this sheet only collects the values
/// and calls back via `onSave`. `onDelete` is non-nil only for the
/// edit path so the destructive button stays out of the add flow.
struct ConnectionDateEditSheet: View {
    let target: ConnectionDateEditTarget
    let onSave: (_ label: String, _ date: String, _ recurrence: ConnectionDateRecurrence) async -> Void
    let onDelete: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var labelDraft: String = ""
    @State private var dateDraft: Date = Date()
    @State private var recurrenceDraft: ConnectionDateRecurrence = .yearly
    @State private var saving = false
    @State private var deleting = false
    @State private var didSeed = false
    @State private var showDeleteConfirm = false

    private var canSave: Bool {
        !labelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
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
            .navigationTitle(target.isEditing ? "Edit date" : "Add date")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.sacredMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(target.isEditing ? "Save" : "Add") {
                        Task { await save() }
                    }
                    .foregroundColor(canSave ? .sacredGold : .sacredMutedLight)
                    .disabled(!canSave || saving || deleting)
                }
            }
        }
        .onAppear { seed() }
        .confirmationDialog(
            "Delete this date?",
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
                    recurrenceRow(title: "One-time", value: .once)
                }
            }
        }
    }

    private func recurrenceRow(
        title: String,
        value: ConnectionDateRecurrence
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
                Text(deleting ? "Deleting…" : "Delete date")
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
        case .new(let initialLabel):
            if let initialLabel, !initialLabel.isEmpty {
                labelDraft = initialLabel
            }
        case .edit(let entry):
            labelDraft = entry.label
            dateDraft = parseISODate(entry.date) ?? Date()
            recurrenceDraft = entry.recurrence
        }
    }

    private func save() async {
        let trimmed = labelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        saving = true
        defer { saving = false }
        await onSave(trimmed, formatISODate(dateDraft), recurrenceDraft)
    }

    private func delete() async {
        guard let onDelete else { return }
        deleting = true
        defer { deleting = false }
        await onDelete()
    }

    private func parseISODate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)
    }

    private func formatISODate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }
}
