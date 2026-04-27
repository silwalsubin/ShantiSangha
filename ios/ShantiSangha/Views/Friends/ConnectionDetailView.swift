import SwiftUI

/// Per-connection detail screen — shows Person identity at the top
/// (real name, location, optional birthday/contact), then editable
/// Connection overlay (relation, nickname, private notes), then a
/// destructive "Remove from circle" action at the bottom.
///
/// For local Persons, both the About-them and Connection-overlay
/// sections are editable. For linked Persons that aren't the caller,
/// About-them is read-only — the user controls their own data; you
/// only annotate.
struct ConnectionDetailView: View {
    let connectionId: UUID
    @ObservedObject var vm: CircleViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profile: ProfileService

    // Connection overlay drafts
    @State private var nicknameDraft: String = ""
    @State private var notesDraft: String = ""
    @State private var relationType: ConnectionType = .friend
    @State private var customRelationDraft: String = ""

    // Person drafts (only used when canEditPerson is true)
    @State private var displayNameDraft: String = ""
    @State private var birthDateDraft: Date?
    @State private var phoneDraft: String = ""
    @State private var emailDraft: String = ""
    @State private var cityDraft: String = ""
    @State private var stateDraft: String = ""
    @State private var countryDraft: String = ""

    @State private var savingNickname = false
    @State private var savingNotes = false
    @State private var savingRelation = false
    @State private var savingPerson = false
    @State private var saveError: String?
    @State private var showRemoveConfirm = false
    @State private var removing = false
    @State private var didSeed = false

    private var connection: Connection? {
        vm.connections.first(where: { $0.id == connectionId })
    }

    private var canEditPerson: Bool {
        connection?.canEditPerson(viewerUserId: profile.currentUserId) ?? false
    }

    var body: some View {
        ScrollView {
            if let connection {
                VStack(spacing: SacredSpacing.l) {
                    header(connection)
                    aboutSection(connection)
                    relationSection
                    nicknameSection
                    notesSection
                    removeSection(connection)
                }
                .padding(.horizontal, SacredSpacing.m)
                .padding(.vertical, SacredSpacing.l)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .background(SacredBackground().ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { seedDrafts() }
        .onChange(of: connection?.id) { _, _ in seedDrafts(force: true) }
    }

    // MARK: - Sections

    private func header(_ c: Connection) -> some View {
        VStack(spacing: SacredSpacing.s) {
            SacredAvatar(
                displayName: c.person.displayName,
                avatarUrl: c.person.avatarUrl,
                size: 120)

            Text(c.person.displayName)
                .font(.sacredHeading)
                .foregroundColor(.sacredText)
                .multilineTextAlignment(.center)

            Text(c.relationLabel)
                .font(.sacredMicroBold)
                .foregroundColor(.sacredGold)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().stroke(Color.sacredGold.opacity(0.3), lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SacredSpacing.m)
    }

    @ViewBuilder
    private func aboutSection(_ c: Connection) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("ABOUT THEM")

            SacredListCard {
                VStack(spacing: 0) {
                    if canEditPerson {
                        editableRow("Name", text: $displayNameDraft, onCommit: { Task { await savePerson() } })
                        Divider().padding(.leading, 16)
                        editableDateRow("Birthday", date: $birthDateDraft, onCommit: { Task { await savePerson() } })
                        Divider().padding(.leading, 16)
                        editableRow("Phone", text: $phoneDraft, keyboard: .phonePad, onCommit: { Task { await savePerson() } })
                        Divider().padding(.leading, 16)
                        editableRow("Email", text: $emailDraft, keyboard: .emailAddress, onCommit: { Task { await savePerson() } })
                        Divider().padding(.leading, 16)
                        editableRow("City", text: $cityDraft, onCommit: { Task { await savePerson() } })
                        Divider().padding(.leading, 16)
                        editableRow("State", text: $stateDraft, onCommit: { Task { await savePerson() } })
                        Divider().padding(.leading, 16)
                        editableRow("Country", text: $countryDraft, onCommit: { Task { await savePerson() } })
                    } else {
                        readOnlyRow("Name", value: c.person.displayName)
                        if let bd = c.person.birthDate, !bd.isEmpty {
                            Divider().padding(.leading, 16)
                            readOnlyRow("Birthday", value: bd)
                        }
                        if let loc = c.person.locationString {
                            Divider().padding(.leading, 16)
                            readOnlyRow("Location", value: loc)
                        }
                    }

                    if savingPerson {
                        savingFooter
                    }
                }
            }

            if !canEditPerson {
                Text("They control this — you can only see what they share.")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var relationSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("RELATIONSHIP")

            SacredListCard {
                VStack(spacing: 0) {
                    Picker("Type", selection: $relationType) {
                        ForEach(ConnectionType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.sacredGold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: relationType) { _, _ in
                        // Custom-label reset is handled server-side when type
                        // moves away from .other; sending the change immediately
                        // keeps the row consistent without waiting for a
                        // separate save action.
                        Task { await saveRelation() }
                    }

                    if relationType == .other {
                        Divider().padding(.leading, 16)
                        TextField("Custom label (e.g. neighbor, mentor)",
                                  text: $customRelationDraft)
                            .font(.sacredText)
                            .foregroundColor(.sacredText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .submitLabel(.done)
                            .onSubmit { Task { await saveRelation() } }
                    }

                    if savingRelation {
                        savingFooter
                    }
                }
            }
        }
    }

    private var nicknameSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("NICKNAME")

            SacredListCard {
                HStack(spacing: 10) {
                    TextField("Add a nickname", text: $nicknameDraft)
                        .font(.sacredText)
                        .foregroundColor(.sacredText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .submitLabel(.done)
                        .onSubmit { Task { await saveNickname() } }

                    if savingNickname {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.sacredGold)
                            .padding(.trailing, 14)
                    }
                }
            }

            Text("Replaces their name everywhere on your end.")
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
                .padding(.horizontal, 4)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("PRIVATE NOTES")

            SacredListCard {
                ZStack(alignment: .topLeading) {
                    if notesDraft.isEmpty {
                        Text("What you notice about them.")
                            .font(.sacredText)
                            .foregroundColor(.sacredMutedLight)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 18)
                    }
                    TextEditor(text: $notesDraft)
                        .font(.sacredText)
                        .foregroundColor(.sacredText)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(minHeight: 120)
                        .onChange(of: notesDraft) { _, _ in scheduleNotesSave() }
                }

                if savingNotes {
                    savingFooter
                }
            }

            Text("Only you can see this.")
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
                .padding(.horizontal, 4)
        }
    }

    private func removeSection(_ c: Connection) -> some View {
        VStack(spacing: SacredSpacing.s) {
            if let saveError {
                Text(saveError)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SacredSpacing.s)
            }

            Button(role: .destructive) {
                showRemoveConfirm = true
            } label: {
                HStack {
                    if removing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.sacredRed)
                    }
                    Text(removing ? "Removing…" : "Remove from circle")
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
            .disabled(removing)
        }
        .padding(.top, SacredSpacing.l)
        .confirmationDialog(
            removeConfirmTitle(c),
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task { await remove() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removeConfirmMessage(c))
        }
    }

    // MARK: - Editable rows

    private func editableRow(
        _ label: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        onCommit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.sacredMicroBold)
                .foregroundColor(.sacredLabel)
                .frame(width: 80, alignment: .leading)
            TextField("Add", text: text)
                .font(.sacredText)
                .foregroundColor(.sacredText)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
                .submitLabel(.done)
                .onSubmit(onCommit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func editableDateRow(
        _ label: String,
        date: Binding<Date?>,
        onCommit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.sacredMicroBold)
                .foregroundColor(.sacredLabel)
                .frame(width: 80, alignment: .leading)
            DatePicker(
                "",
                selection: Binding(
                    get: { date.wrappedValue ?? Date() },
                    set: { date.wrappedValue = $0; onCommit() }),
                displayedComponents: [.date]
            )
            .labelsHidden()
            .tint(.sacredGold)
            Spacer(minLength: 0)
            if date.wrappedValue != nil {
                Button {
                    date.wrappedValue = nil
                    onCommit()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.sacredMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func readOnlyRow(_ label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.sacredMicroBold)
                .foregroundColor(.sacredLabel)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.sacredText)
                .foregroundColor(.sacredText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var savingFooter: some View {
        HStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
                .tint(.sacredGold)
            Text("Saving…")
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.sacredSectionLabel)
            .foregroundColor(.sacredLabel)
            .padding(.horizontal, 4)
    }

    // MARK: - Save flows

    private func seedDrafts(force: Bool = false) {
        guard let c = connection else { return }
        guard !didSeed || force else { return }
        nicknameDraft = c.nickname ?? ""
        notesDraft = c.privateNotes ?? ""
        relationType = ConnectionType(rawValue: c.relationType.lowercased()) ?? .friend
        customRelationDraft = c.customRelationLabel ?? ""
        displayNameDraft = c.person.displayName
        birthDateDraft = parseISODate(c.person.birthDate)
        phoneDraft = c.person.phoneNumber ?? ""
        emailDraft = c.person.email ?? ""
        cityDraft = c.person.city ?? ""
        stateDraft = c.person.state ?? ""
        countryDraft = c.person.country ?? ""
        didSeed = true
    }

    private func saveNickname() async {
        guard let c = connection else { return }
        let trimmed = nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = c.nickname ?? ""
        if trimmed == original { return }

        savingNickname = true
        defer { savingNickname = false }
        do {
            if trimmed.isEmpty {
                _ = try await vm.updateOverlay(connectionId: c.id, clearNickname: true)
            } else {
                _ = try await vm.updateOverlay(connectionId: c.id, nickname: trimmed)
            }
            saveError = nil
        } catch {
            saveError = "Couldn't save. Try again."
        }
    }

    private func scheduleNotesSave() {
        let snapshot = notesDraft
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if snapshot == notesDraft {
                await saveNotes()
            }
        }
    }

    private func saveNotes() async {
        guard let c = connection else { return }
        let original = c.privateNotes ?? ""
        if notesDraft == original { return }
        savingNotes = true
        defer { savingNotes = false }
        do {
            if notesDraft.isEmpty {
                _ = try await vm.updateOverlay(connectionId: c.id, clearPrivateNotes: true)
            } else {
                _ = try await vm.updateOverlay(connectionId: c.id, privateNotes: notesDraft)
            }
            saveError = nil
        } catch {
            saveError = "Couldn't save. Try again."
        }
    }

    private func saveRelation() async {
        guard let c = connection else { return }
        savingRelation = true
        defer { savingRelation = false }
        do {
            let label: String?
            let clearLabel: Bool
            if relationType == .other {
                let trimmed = customRelationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    // Don't push an "other" with no label — backend would 422.
                    return
                }
                label = trimmed
                clearLabel = false
            } else {
                label = nil
                clearLabel = c.customRelationLabel != nil
            }
            _ = try await vm.updateOverlay(
                connectionId: c.id,
                relationType: relationType,
                customRelationLabel: label,
                clearCustomRelationLabel: clearLabel)
            saveError = nil
        } catch {
            saveError = "Couldn't update relationship. Try again."
        }
    }

    private func savePerson() async {
        guard let c = connection, canEditPerson else { return }
        savingPerson = true
        defer { savingPerson = false }
        do {
            let req = UpdatePersonRequest(
                displayName: displayNameDraft.trimmed.isEmpty ? nil : displayNameDraft.trimmed,
                birthDate: birthDateDraft.flatMap(formatISODate),
                phoneNumber: phoneDraft.trimmed.isEmpty ? nil : phoneDraft.trimmed,
                email: emailDraft.trimmed.isEmpty ? nil : emailDraft.trimmed,
                country: countryDraft.trimmed.isEmpty ? nil : countryDraft.trimmed,
                state: stateDraft.trimmed.isEmpty ? nil : stateDraft.trimmed,
                city: cityDraft.trimmed.isEmpty ? nil : cityDraft.trimmed,
                clearBirthDate: birthDateDraft == nil && c.person.birthDate != nil ? true : nil,
                clearPhoneNumber: phoneDraft.trimmed.isEmpty && c.person.phoneNumber != nil ? true : nil,
                clearEmail: emailDraft.trimmed.isEmpty && c.person.email != nil ? true : nil,
                clearCountry: countryDraft.trimmed.isEmpty && c.person.country != nil ? true : nil,
                clearState: stateDraft.trimmed.isEmpty && c.person.state != nil ? true : nil,
                clearCity: cityDraft.trimmed.isEmpty && c.person.city != nil ? true : nil)
            _ = try await vm.updatePerson(connectionId: c.id, request: req)
            saveError = nil
        } catch {
            saveError = "Couldn't save. Try again."
        }
    }

    private func remove() async {
        guard let c = connection else { return }
        removing = true
        defer { removing = false }
        do {
            try await vm.delete(connectionId: c.id)
            dismiss()
        } catch {
            saveError = "Couldn't remove. Try again."
        }
    }

    private func removeConfirmTitle(_ c: Connection) -> String {
        if c.messageable {
            return "Remove \(c.person.displayName) from your circle?"
        }
        return "Remove \(c.person.displayName)?"
    }

    private func removeConfirmMessage(_ c: Connection) -> String {
        if c.messageable {
            return "Your message thread and any media will be deleted on both sides. This can't be undone."
        }
        return "They'll no longer appear in your circle. This can't be undone."
    }

    // MARK: - Helpers

    private func parseISODate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
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

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
