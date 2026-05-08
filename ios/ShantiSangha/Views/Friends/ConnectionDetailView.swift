import SwiftUI
import Contacts
import ContactsUI

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
    @State private var contactToSave: ContactItem?
    @State private var showContactPicker = false
    @State private var linkedContact: LinkedContactSnapshot?

    // Birth-chart sharing — directional. `iShared` = current user has shared
    // their chart with this friend. `theyShared` = friend has shared with
    // current user; gates the "[Name] through your chart" affordance below.
    @State private var iShared: Bool = false
    @State private var theyShared: Bool = false
    @State private var loadingShareState: Bool = true
    @State private var togglingShare: Bool = false

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
                    if let linkedContact {
                        linkedContactSection(linkedContact)
                    }
                    if connection.messageable {
                        birthChartSection(connection)
                    }
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
        .onAppear {
            seedDrafts()
            linkedContact = LinkedContactStore.snapshot(for: connectionId)
            Task { await loadShareState() }
        }
        .onChange(of: connection?.id) { _, _ in
            seedDrafts(force: true)
            linkedContact = LinkedContactStore.snapshot(for: connectionId)
            Task { await loadShareState() }
        }
        .sheet(item: $contactToSave) { item in
            AddContactSheet(contact: item.contact) {
                contactToSave = nil
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPickerSheet { picked in
                showContactPicker = false
                applyPickedContact(picked)
            } onCancel: {
                showContactPicker = false
            }
            .ignoresSafeArea()
        }
    }

    /// Identifiable wrapper so the contact sheet can drive its presentation
    /// via `.sheet(item:)` — `CNContact` doesn't conform to Identifiable.
    private struct ContactItem: Identifiable {
        let id = UUID()
        let contact: CNContact
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

            headerActions(c)
                .padding(.top, SacredSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SacredSpacing.m)
    }

    @ViewBuilder
    private func headerActions(_ c: Connection) -> some View {
        HStack(spacing: SacredSpacing.s) {
            if c.messageable {
                NavigationLink(destination: FriendChatView(connection: c, circleVM: vm)) {
                    HeaderActionPill(icon: "bubble.left.and.bubble.right", label: "Message")
                }
                .buttonStyle(.plain)
            }

            Button {
                contactToSave = ContactItem(contact: contactFromPerson(c.person, displayLabel: c.displayLabel))
            } label: {
                HeaderActionPill(icon: "person.crop.circle.badge.plus", label: "Save")
            }
            .buttonStyle(.plain)

            Button {
                showContactPicker = true
            } label: {
                HeaderActionPill(
                    icon: linkedContact == nil ? "link" : "link.circle.fill",
                    label: linkedContact == nil ? "Link" : "Linked")
            }
            .buttonStyle(.plain)
        }
    }

    /// Snapshots the picked iPhone contact's fields into local storage,
    /// keyed by this connection's id. Never touches the backend Person
    /// record — paired ShantiSangha users own their own data, and even
    /// for local persons we prefer to keep "your view" of someone
    /// separate from "what they share".
    private func applyPickedContact(_ contact: CNContact) {
        let snapshot = LinkedContactSnapshot(from: contact)
        LinkedContactStore.setSnapshot(snapshot, for: connectionId)
        linkedContact = snapshot
    }

    private func unlinkContact() {
        LinkedContactStore.setSnapshot(nil, for: connectionId)
        linkedContact = nil
    }

    @ViewBuilder
    private func linkedContactSection(_ snapshot: LinkedContactSnapshot) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("LINKED CONTACT")

            SacredListCard {
                VStack(spacing: 0) {
                    readOnlyRow("Name", value: snapshot.fullName)
                    if let phone = snapshot.phoneNumber {
                        Divider().padding(.leading, 16)
                        readOnlyRow("Phone", value: phone)
                    }
                    if let email = snapshot.email {
                        Divider().padding(.leading, 16)
                        readOnlyRow("Email", value: email)
                    }
                    if let address = snapshot.address {
                        Divider().padding(.leading, 16)
                        readOnlyRow("Address", value: address)
                    }
                    if let bd = snapshot.birthDate {
                        Divider().padding(.leading, 16)
                        readOnlyRow("Birthday", value: bd)
                    }

                    Divider().padding(.leading, 16)
                    Button { unlinkContact() } label: {
                        Text("Unlink contact")
                            .font(.sacredTextMedium)
                            .foregroundColor(.sacredRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }

            Text("Only you see this — pulled from your iPhone contacts and stored on this device.")
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
                .padding(.horizontal, SacredSpacing.xs)
        }
    }

    private func contactFromPerson(_ person: Person, displayLabel: String) -> CNContact {
        let contact = CNMutableContact()

        let parts = displayLabel.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        contact.givenName = parts.first.map(String.init) ?? displayLabel
        if parts.count > 1 { contact.familyName = String(parts[1]) }

        if let phone = person.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
            contact.phoneNumbers = [
                CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))
            ]
        }

        if let email = person.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            contact.emailAddresses = [
                CNLabeledValue(label: CNLabelHome, value: email as NSString)
            ]
        }

        let street = person.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let city = person.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let state = person.state?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let country = person.country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !(street.isEmpty && city.isEmpty && state.isEmpty && country.isEmpty) {
            let addr = CNMutablePostalAddress()
            addr.street = street
            addr.city = city
            addr.state = state
            addr.country = country
            contact.postalAddresses = [
                CNLabeledValue(label: CNLabelHome, value: addr)
            ]
        }

        if let bd = person.birthDate {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = df.date(from: bd) {
                contact.birthday = Calendar(identifier: .gregorian)
                    .dateComponents([.year, .month, .day], from: date)
            }
        }

        return contact
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
                    Menu {
                        // Pinned-down menu items, with a checkmark on the
                        // current selection so the open menu reads like a
                        // sacred-styled list rather than a system Picker.
                        ForEach(ConnectionType.allCases) { type in
                            Button {
                                relationType = type
                                // Custom-label reset is handled server-side when
                                // type moves away from .other; sending the change
                                // immediately keeps the row consistent without
                                // waiting for a separate save action.
                                Task { await saveRelation() }
                            } label: {
                                if relationType == type {
                                    Label(type.label, systemImage: "checkmark")
                                } else {
                                    Text(type.label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.fill")
                                .font(.sacredSmallSemibold)
                                .foregroundColor(.sacredGold)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.sacredGold.opacity(0.12)))

                            Text(relationType.label)
                                .font(.sacredTextSemibold)
                                .foregroundColor(.sacredText)

                            Spacer(minLength: 4)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.sacredMicro)
                                .foregroundColor(.sacredMuted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

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

    @ViewBuilder
    private func birthChartSection(_ c: Connection) -> some View {
        // Only meaningful when the friend has a real ShantiSangha userId; the
        // toggle gates on .messageable upstream so this assertion is safe.
        let friendUserId = c.person.userId

        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("BIRTH CHART")

            SacredListCard {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share my chart with \(c.displayLabel)")
                                .font(.sacredTextMedium)
                                .foregroundColor(.sacredText)
                            Text("They can read your chart privately. Your raw birth data isn't shown.")
                                .font(.sacredMicro)
                                .foregroundColor(.sacredMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if togglingShare {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.sacredGold)
                                .frame(width: 51, height: 31)
                        } else if let friendUserId {
                            Toggle("", isOn: Binding(
                                get: { iShared },
                                set: { newValue in
                                    Task { await setShare(to: newValue, friendUserId: friendUserId) }
                                }))
                                .labelsHidden()
                                .tint(.sacredGold)
                                .disabled(loadingShareState)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    if theyShared, let friendUserId {
                        Divider().padding(.leading, 16)
                        NavigationLink(destination: PairReadingView(
                            subjectUserId: friendUserId,
                            subjectName: c.displayLabel)) {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.sacredGold)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(c.displayLabel) through your chart")
                                        .font(.sacredTextMedium)
                                        .foregroundColor(.sacredText)
                                    Text("A private four-section reading")
                                        .font(.sacredMicro)
                                        .foregroundColor(.sacredMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.sacredMutedLight)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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

    private func loadShareState() async {
        guard let c = connection, c.messageable, let friendUserId = c.person.userId else {
            iShared = false; theyShared = false
            loadingShareState = false
            return
        }
        loadingShareState = true
        defer { loadingShareState = false }
        do {
            let shares = try await BirthDetailSharesAPI.myShares()
            iShared = shares.grantedTo.contains(friendUserId)
            theyShared = shares.receivedFrom.contains(friendUserId)
        } catch {
            // Non-critical — leave defaults; the UI just shows the off state
            // until the next refresh.
        }
    }

    private func setShare(to newValue: Bool, friendUserId: UUID) async {
        let prev = iShared
        iShared = newValue            // optimistic UI
        togglingShare = true
        defer { togglingShare = false }
        do {
            if newValue {
                _ = try await BirthDetailSharesAPI.grant(to: friendUserId)
            } else {
                try await BirthDetailSharesAPI.revoke(from: friendUserId)
            }
            saveError = nil
        } catch {
            iShared = prev            // revert on failure
            saveError = "Couldn't update sharing. Try again."
        }
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

/// Snapshot of an iPhone contact taken at link time. Persisted on
/// device only — nothing flows to the backend, so paired users'
/// records stay untouched.
private struct LinkedContactSnapshot: Codable, Equatable {
    let identifier: String
    let givenName: String
    let familyName: String
    let phoneNumber: String?
    let email: String?
    let address: String?
    let birthDate: String?

    var fullName: String {
        let parts = [givenName, familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Linked contact" : parts.joined(separator: " ")
    }

    init(from contact: CNContact) {
        self.identifier = contact.identifier
        self.givenName = contact.givenName
        self.familyName = contact.familyName

        let phone = contact.phoneNumbers.first?.value.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.phoneNumber = (phone?.isEmpty == false) ? phone : nil

        let mail = (contact.emailAddresses.first?.value as String?)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = (mail?.isEmpty == false) ? mail : nil

        if let pa = contact.postalAddresses.first?.value {
            let parts = [pa.street, pa.city, pa.state, pa.country]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            self.address = parts.isEmpty ? nil : parts.joined(separator: ", ")
        } else {
            self.address = nil
        }

        if let bd = contact.birthday,
           let date = Calendar(identifier: .gregorian).date(from: bd) {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            self.birthDate = f.string(from: date)
        } else {
            self.birthDate = nil
        }
    }
}

/// Per-connection iPhone-contact links, persisted in UserDefaults as
/// a single JSON-encoded `[connectionId: snapshot]` blob. Local-only
/// — nothing here ever leaves the device.
private enum LinkedContactStore {
    private static let key = "linked_contacts_v1"

    static func snapshot(for connectionId: UUID) -> LinkedContactSnapshot? {
        loadAll()[connectionId.uuidString]
    }

    static func setSnapshot(_ snapshot: LinkedContactSnapshot?,
                            for connectionId: UUID) {
        var dict = loadAll()
        if let snapshot {
            dict[connectionId.uuidString] = snapshot
        } else {
            dict.removeValue(forKey: connectionId.uuidString)
        }
        save(dict)
    }

    private static func loadAll() -> [String: LinkedContactSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: LinkedContactSnapshot].self, from: data)
        else { return [:] }
        return dict
    }

    private static func save(_ dict: [String: LinkedContactSnapshot]) {
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

private struct HeaderActionPill: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.sacredSmallSemibold)
            Text(label)
                .font(.sacredSmallSemibold)
                .lineLimit(1)
        }
        .foregroundColor(.sacredGold)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(Capsule().fill(Color.sacredGold.opacity(0.12)))
        .overlay(Capsule().stroke(Color.sacredGold.opacity(0.25), lineWidth: 1))
    }
}

/// Wraps `CNContactPickerViewController` so the user can pick an
/// existing iPhone contact. iOS hands back a `CNContact` with only
/// the keys we ask for — no permission prompt is needed for the
/// picker itself; the system gates field access via the picker.
private struct ContactPickerSheet: UIViewControllerRepresentable {
    let onPick: (CNContact) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactPostalAddressesKey,
            CNContactBirthdayKey
        ]
        return picker
    }

    func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (CNContact) -> Void
        let onCancel: () -> Void
        init(onPick: @escaping (CNContact) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick(contact)
        }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onCancel()
        }
    }
}

/// Wraps `CNContactViewController(forNewContact:)` in a navigation
/// controller so it can be presented as a SwiftUI sheet. The system
/// handles the contacts permission prompt when the user taps Done.
private struct AddContactSheet: UIViewControllerRepresentable {
    let contact: CNContact
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = CNContactViewController(forNewContact: contact)
        vc.delegate = context.coordinator
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ vc: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func contactViewController(_ viewController: CNContactViewController,
                                   didCompleteWith contact: CNContact?) {
            onDismiss()
        }
    }
}
