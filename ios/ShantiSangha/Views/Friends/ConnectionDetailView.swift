import SwiftUI

/// Per-connection detail screen — shows Person identity at the top
/// (real name, location, optional contact), then editable Connection
/// overlay (relation, nickname, private notes), then a destructive
/// "Remove from circle" action at the bottom.
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
    @State private var circlesDraft: [String] = []
    @State private var showCirclesPicker = false

    // Person drafts (only used when canEditPerson is true)
    @State private var displayNameDraft: String = ""
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

    // nil = sheet closed; .new = adding; .edit(id) = editing existing
    @State private var dateEditTarget: ConnectionDateEditTarget?
    @State private var datesExpanded = false

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
                    datesSection(connection)
                    nicknameSection
                    notesSection
                    ConnectionAttachmentsView(connectionId: connection.id)
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
        .sheet(item: $dateEditTarget) { target in
            ConnectionDateEditSheet(
                target: target,
                onSave: { label, date, recurrence in
                    await saveDate(
                        target: target,
                        label: label,
                        date: date,
                        recurrence: recurrence)
                },
                onDelete: target.isEditing
                    ? { await deleteDate(target: target) }
                    : nil)
        }
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

            if !c.circlesLabel.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "atom")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.sacredGold)
                    Text(c.circlesLabel)
                        .font(.sacredMicroBold)
                        .foregroundColor(.sacredGold)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().stroke(Color.sacredGold.opacity(0.3), lineWidth: 1))
            }

            headerActions(c)
                .padding(.top, SacredSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SacredSpacing.m)
        .background(AvatarBackdrop(avatarUrl: c.person.avatarUrl))
    }

    @ViewBuilder
    private func headerActions(_ c: Connection) -> some View {
        if c.messageable {
            NavigationLink(destination: FriendChatView(connection: c, circleVM: vm)) {
                HeaderActionPill(icon: "bubble.left.and.bubble.right", label: "Message")
            }
            .buttonStyle(.plain)
        }
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
            sectionLabel("CIRCLES")

            SacredListCard {
                VStack(spacing: 0) {
                    CircleChipsRow(
                        circles: circlesDraft,
                        onRemove: { name in
                            circlesDraft.removeAll {
                                $0.caseInsensitiveCompare(name) == .orderedSame
                            }
                            Task { await saveCircles() }
                        },
                        onAdd: { showCirclesPicker = true })

                    if savingRelation {
                        savingFooter
                    }
                }
            }

            Text("Tag this person with one or more circles — Friend, Coworker, Family, anything you want.")
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
                .padding(.horizontal, 4)

            PrivateFootnote()
        }
        .sheet(isPresented: $showCirclesPicker) {
            CirclesPickerSheet(
                catalog: vm.circleCatalog,
                alreadyAdded: Set(circlesDraft),
                onPick: { name in
                    addCircle(name)
                    showCirclesPicker = false
                },
                onCancel: { showCirclesPicker = false })
        }
    }

    private func addCircle(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if circlesDraft.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return
        }
        circlesDraft.append(trimmed)
        Task { await saveCircles() }
    }

    private func datesSection(_ c: Connection) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("IMPORTANT DATES")
            if c.dates.isEmpty {
                emptyDatesPresets
            } else {
                SacredListCard {
                    VStack(spacing: 0) {
                        // Always show the first date so the section
                        // never reads as empty; "+ N more" lets the
                        // rest live one tap away when the user has
                        // accumulated several.
                        let visible = datesExpanded ? c.dates : Array(c.dates.prefix(1))
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                            SacredDateRow(
                                date: parseISODate(entry.date) ?? Date(),
                                label: entry.label,
                                onTap: { dateEditTarget = .edit(entry) })
                            if index < visible.count - 1 {
                                Divider().padding(.leading, 64)
                            }
                        }
                        if c.dates.count > 1 {
                            Divider().padding(.leading, 16)
                            datesToggleRow(remaining: c.dates.count - 1)
                        }
                        Divider().padding(.leading, 16)
                        addDateButton(label: "Add another")
                    }
                }
            }

            PrivateFootnote()
        }
    }

    /// Single row that flips between "+ N more" (collapsed) and
    /// "Show less" (expanded) so the rest of the dates stay one tap
    /// away in either direction without claiming a separate header
    /// chevron.
    private func datesToggleRow(remaining: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                datesExpanded.toggle()
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: datesExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                Text(datesExpanded ? "Show less" : "+ \(remaining) more")
                    .font(.sacredSmallSemibold)
                Spacer()
            }
            .foregroundColor(.sacredGold)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Empty-state suggestion list. Each preset opens the date sheet
    /// pre-filled with that label so first-time users get a one-tap
    /// path; the subtitles double as scaffolding for what each kind
    /// of date is for.
    private var emptyDatesPresets: some View {
        SacredListCard {
            VStack(spacing: 0) {
                datePresetRow(
                    label: "Birthday",
                    subtitle: "Their day, every year")
                Divider().padding(.leading, 16)
                datePresetRow(
                    label: "Anniversary",
                    subtitle: "Wedding, partnership, milestone")
                Divider().padding(.leading, 16)
                datePresetRow(
                    label: "Day we met",
                    subtitle: "When your paths crossed")
                Divider().padding(.leading, 16)
                datePresetRow(
                    label: nil,
                    subtitle: "Anything else worth remembering")
            }
        }
    }

    private func datePresetRow(label: String?, subtitle: String) -> some View {
        Button {
            dateEditTarget = .new(initialLabel: label)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: label == nil ? "plus.circle" : "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.sacredGold)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label ?? "Custom date")
                        .font(.sacredTextSemibold)
                        .foregroundColor(.sacredText)
                    Text(subtitle)
                        .font(.sacredMicro)
                        .foregroundColor(.sacredMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.sacredMuted.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addDateButton(label: String) -> some View {
        Button {
            dateEditTarget = .new()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.sacredSmallSemibold)
                Spacer()
            }
            .foregroundColor(.sacredGold)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

            PrivateFootnote()
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

            PrivateFootnote()
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
        circlesDraft = c.circles
        displayNameDraft = c.person.displayName
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

    private func saveCircles() async {
        guard let c = connection else { return }
        if c.circles.elementsEqual(circlesDraft, by: { $0 == $1 }) { return }
        savingRelation = true
        defer { savingRelation = false }
        do {
            _ = try await vm.updateOverlay(
                connectionId: c.id,
                circles: circlesDraft)
            saveError = nil
        } catch {
            saveError = "Couldn't update circles. Try again."
        }
    }

    private func savePerson() async {
        guard let c = connection, canEditPerson else { return }
        savingPerson = true
        defer { savingPerson = false }
        do {
            let req = UpdatePersonRequest(
                displayName: displayNameDraft.trimmed.isEmpty ? nil : displayNameDraft.trimmed,
                phoneNumber: phoneDraft.trimmed.isEmpty ? nil : phoneDraft.trimmed,
                email: emailDraft.trimmed.isEmpty ? nil : emailDraft.trimmed,
                country: countryDraft.trimmed.isEmpty ? nil : countryDraft.trimmed,
                state: stateDraft.trimmed.isEmpty ? nil : stateDraft.trimmed,
                city: cityDraft.trimmed.isEmpty ? nil : cityDraft.trimmed,
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

    private func saveDate(
        target: ConnectionDateEditTarget,
        label: String,
        date: String,
        recurrence: ConnectionDateRecurrence
    ) async {
        guard let c = connection else { return }
        do {
            switch target {
            case .new:
                _ = try await vm.addDate(
                    connectionId: c.id,
                    label: label,
                    date: date,
                    recurrence: recurrence)
            case .edit(let entry):
                _ = try await vm.updateDate(
                    connectionId: c.id,
                    dateId: entry.id,
                    label: label,
                    date: date,
                    recurrence: recurrence)
            }
            saveError = nil
            dateEditTarget = nil
        } catch {
            saveError = "Couldn't save. Try again."
        }
    }

    private func deleteDate(target: ConnectionDateEditTarget) async {
        guard let c = connection, case .edit(let entry) = target else { return }
        do {
            try await vm.deleteDate(connectionId: c.id, dateId: entry.id)
            saveError = nil
            dateEditTarget = nil
        } catch {
            saveError = "Couldn't delete. Try again."
        }
    }

    private func parseISODate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)
    }
}

/// Sheet identity for the add/edit-date flow. `.new()` opens an empty
/// form; `.new(initialLabel:)` pre-fills the label so the empty-state
/// preset rows can hand the user a one-tap "Birthday" / "Anniversary"
/// / "Day we met" path; `.edit(entry)` pre-fills the whole row and
/// offers a destructive "Delete" action.
enum ConnectionDateEditTarget: Identifiable {
    case new(initialLabel: String? = nil)
    case edit(ConnectionDate)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let entry): return entry.id.uuidString
        }
    }

    var isEditing: Bool {
        if case .edit = self { return true }
        return false
    }

    var initialLabel: String? {
        if case .new(let label) = self { return label }
        return nil
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Soft, blurred bloom of the connection's avatar painted behind the header.
/// Faded out via a radial mask so the warm sacred background still shows
/// through at the edges — the photo reads as ambient atmosphere, not a
/// second image.
private struct AvatarBackdrop: View {
    let avatarUrl: String?
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .blur(radius: 50)
                    .opacity(0.22)
                    .mask {
                        RadialGradient(
                            colors: [.black, .black.opacity(0.55), .clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: max(geo.size.width, geo.size.height) * 0.55)
                    }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .task(id: avatarUrl) {
            guard let urlString = avatarUrl,
                  !urlString.isEmpty,
                  let url = URL(string: urlString) else {
                image = nil
                return
            }
            image = await AvatarImageCache.shared.image(for: url)
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

/// Horizontal flow of circle chips with an "+ Add circle" trailing pill.
/// Each chip has an ✕ that fires `onRemove`. Tapping the add pill fires
/// `onAdd` so the parent can present `CirclesPickerSheet`.
struct CircleChipsRow: View {
    let circles: [String]
    let onRemove: (String) -> Void
    let onAdd: () -> Void

    var body: some View {
        WrapHStack(spacing: 8, lineSpacing: 8) {
            ForEach(circles, id: \.self) { name in
                chip(name)
            }
            addButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func chip(_ name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "atom")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.sacredGold)
            Text(name)
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredGold)
            Button { onRemove(name) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.sacredGold.opacity(0.7))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 32)
        .background(Capsule().fill(Color.sacredGold.opacity(0.12)))
        .overlay(Capsule().stroke(Color.sacredGold.opacity(0.3), lineWidth: 1))
    }

    private var addButton: some View {
        Button(action: onAdd) {
            HStack(spacing: 4) {
                Image(systemName: "atom")
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text(circles.isEmpty ? "Add circle" : "Add")
                    .font(.sacredSmallSemibold)
            }
            .foregroundColor(.sacredGold)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .overlay(Capsule().stroke(Color.sacredGold.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        }
        .buttonStyle(.plain)
    }
}

/// Minimal flow layout — wraps children onto new lines when they overflow
/// the available width. Used by `CircleChipsRow` so chip count doesn't
/// blow past the card edge. SwiftUI's `Layout` API would also work, but
/// this lighter `GeometryReader` + measurement approach keeps the file
/// self-contained.
struct WrapHStack<Content: View>: View {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    let content: () -> Content

    init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content
    }

    var body: some View {
        WrapLayout(spacing: spacing, lineSpacing: lineSpacing) {
            content()
        }
    }
}

private struct WrapLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let lines = layout(maxWidth: maxWidth, subviews: subviews)
        let totalHeight = lines.reduce(0) { partial, line in
            partial + (line.height) + (partial == 0 ? 0 : lineSpacing)
        }
        let totalWidth = lines.map(\.width).max() ?? 0
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lines = layout(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            for entry in line.entries {
                let size = entry.size
                subviews[entry.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private func layout(maxWidth: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var current = Line()

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let projected = current.entries.isEmpty ? size.width : current.width + spacing + size.width
            if projected > maxWidth && !current.entries.isEmpty {
                lines.append(current)
                current = Line()
            }
            let xOffset = current.entries.isEmpty ? 0 : current.width + spacing
            current.entries.append(.init(index: index, size: size))
            current.width = xOffset + size.width
            current.height = max(current.height, size.height)
        }
        if !current.entries.isEmpty { lines.append(current) }
        return lines
    }

    private struct Line {
        var entries: [Entry] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
    private struct Entry {
        let index: Int
        let size: CGSize
    }
}

