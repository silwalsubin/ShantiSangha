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

    // Connection overlay edit state. Nickname and Notes use the same
    // sheet pattern the personal account flow uses on Home; circlesDraft
    // remains because the circles editor is still inline today.
    @State private var activeOverlayEdit: ConnectionOverlayEdit?
    @State private var circlesDraft: [String] = []
    @State private var showCirclesPicker = false

    // Person drafts (only used when canEditPerson is true)
    @State private var displayNameDraft: String = ""
    @State private var phoneDraft: String = ""
    @State private var emailDraft: String = ""
    @State private var cityDraft: String = ""
    @State private var stateDraft: String = ""
    @State private var countryDraft: String = ""

    @State private var savingRelation = false
    @State private var savingPerson = false
    @State private var saveError: String?
    @State private var showRemoveConfirm = false
    @State private var removing = false
    @State private var didSeed = false

    // Owner-private avatar editor — pencil tap opens the same sheet
    // chrome the personal profile picture uses; AvatarPickerBody owns
    // the picker + crop + Save, plus an optional Remove button when
    // the connection already has a private avatar.
    @State private var showAvatarPickerSheet = false

    // nil = sheet closed; .new = adding; .edit(id) = editing existing
    @State private var dateEditTarget: ReminderEditTarget?
    @State private var datesExpanded = false

    /// Connection-scoped reminders fetched via `/api/reminders?connectionId=…`.
    /// Loaded on first appear and refreshed after each create/update/delete.
    @State private var dates: [Reminder] = []
    @State private var datesLoading = false

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
                    chatMediaFilesRow(connection)
                    mediaFilesRow(connection)
                    relationSection
                    datesSection(connection)
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
        .background {
            // Full-page parchment + a very-subtle avatar wash. The avatar
            // backdrop used to live inside the header section; pulling it
            // out to the page level lets the warmth of the photo flow
            // behind every section instead of cutting off below the avatar.
            ZStack {
                SacredBackground()
                if let connection {
                    AvatarBackdrop(avatarUrl: connection.ownerVisibleAvatarUrl)
                }
            }
            .ignoresSafeArea()
        }
        .navigationTitle(connection?.displayLabel ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { seedDrafts() }
        .onChange(of: connection?.id) { _, _ in seedDrafts(force: true) }
        .sheet(item: $dateEditTarget) { target in
            ReminderEditSheet(
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
        .task(id: connectionId) { await loadDates() }
        .sheet(isPresented: $showAvatarPickerSheet) {
            if let c = connection {
                SacredFormSheet(
                    title: "Profile picture",
                    detent: .height(560),
                    onCancel: { showAvatarPickerSheet = false }
                ) {
                    privateAvatarPickerBody(c)
                }
            }
        }
        .sheet(item: $activeOverlayEdit) { edit in
            if let c = connection {
                SacredFormSheet(
                    title: edit.title,
                    detent: edit.detent,
                    onCancel: { activeOverlayEdit = nil }
                ) {
                    overlayEditBody(edit, connection: c)
                }
            }
        }
    }

    @ViewBuilder
    private func overlayEditBody(_ edit: ConnectionOverlayEdit, connection c: Connection) -> some View {
        switch edit {
        case .nickname:
            ConnectionNicknameEditBody(
                vm: vm,
                connectionId: c.id,
                initialValue: c.nickname ?? "",
                onSaved: { activeOverlayEdit = nil })
        case .notes:
            ConnectionNotesEditBody(
                vm: vm,
                connectionId: c.id,
                initialValue: c.privateNotes ?? "",
                onSaved: { activeOverlayEdit = nil })
        }
    }

    /// Phrasing for the privacy footnote inside the picker — mirrors
    /// the wording used elsewhere for owner-private surfaces, but
    /// adds an extra reassurance for in-app linked Persons that they
    /// won't see this picture from their side.
    private var privateAvatarFootnoteText: String {
        guard let c = connection else { return "Only you can see this." }
        return c.person.userId == nil
            ? "Only you can see this."
            : "Only you will see this. They'll keep showing as their normal photo."
    }

    /// Body for the private-avatar sheet. The shell chrome (title,
    /// Cancel, detent, sacred background) lives in `SacredFormSheet`.
    private func privateAvatarPickerBody(_ c: Connection) -> some View {
        AvatarPickerBody(
            initialAvatarUrl: c.ownerVisibleAvatarUrl,
            submitLabel: "Save",
            upload: { data in
                try await vm.uploadPrivateAvatar(
                    connectionId: c.id,
                    jpegData: data)
            },
            onSaved: { showAvatarPickerSheet = false },
            footnote: AnyView(PrivateFootnote(privateAvatarFootnoteText)),
            removeLabel: c.privateAvatarUrl == nil ? nil : "Remove picture",
            removeAction: c.privateAvatarUrl == nil ? nil : {
                try? await vm.clearPrivateAvatar(connectionId: c.id)
            }
        )
    }

    // MARK: - Sections

    private func header(_ c: Connection) -> some View {
        VStack(spacing: SacredSpacing.s) {
            // Pencil affordance matches the personal profile flow on Home —
            // bottom-trailing is the iOS convention for "edit picture." The
            // atom mark for in-app linked Persons sits at bottom-leading,
            // mirroring the pencil across the avatar's vertical axis so
            // both badges share the same baseline without crowding.
            Button {
                showAvatarPickerSheet = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    SacredAvatar(
                        displayName: c.person.displayName,
                        avatarUrl: c.ownerVisibleAvatarUrl,
                        size: 120)
                        .overlay(alignment: .bottomLeading) {
                            if c.person.userId != nil {
                                // Push the badge so its center sits on the
                                // avatar circle's bottom-leading edge —
                                // half the chip overlaps the photo, half
                                // hangs outside. Geometry: avatar is 120pt
                                // (r=60), badge is 26pt; the 45° edge point
                                // is ≈(17.5, 102.5) in the frame and the
                                // badge's natural bottom-leading center is
                                // (13, 107), so (+5, -5) lands the chip's
                                // center on the curve.
                                Image(systemName: "atom")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.sacredGold)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(Color.sacredBg))
                                    .overlay(Circle().stroke(Color.sacredGold.opacity(0.5), lineWidth: 1.5))
                                    .offset(x: 5, y: -5)
                            }
                        }

                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.sacredGold))
                        .overlay(Circle().stroke(Color.sacredBg, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                c.privateAvatarUrl == nil
                    ? "Add a private picture for this person"
                    : "Change or remove your private picture for this person")

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

            if circlesDraft.isEmpty {
                sectionScaffold("Tag this person with one or more circles — Friend, Coworker, Family, anything you want.")
            }

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
            if dates.isEmpty {
                emptyDatesPresets
            } else {
                SacredListCard {
                    VStack(spacing: 0) {
                        let visible = datesExpanded ? dates : Array(dates.prefix(1))
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                            SacredDateRow(
                                date: parseISODate(entry.date) ?? Date(),
                                label: entry.label,
                                onTap: { dateEditTarget = .edit(entry) })
                            if index < visible.count - 1 {
                                Divider().padding(.leading, 64)
                            }
                        }
                        if dates.count > 1 {
                            Divider().padding(.leading, 16)
                            datesToggleRow(remaining: dates.count - 1)
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
            dateEditTarget = .new(initialLabel: label, connectionId: connectionId)
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
            dateEditTarget = .new(initialLabel: nil, connectionId: connectionId)
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
            Button {
                activeOverlayEdit = .nickname
            } label: {
                SacredListCard {
                    SacredMenuRow(
                        icon: "person.text.rectangle",
                        title: "Nickname",
                        subtitle: nicknameSubtitle)
                }
            }
            .buttonStyle(.plain)

            PrivateFootnote()
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            Button {
                activeOverlayEdit = .notes
            } label: {
                SacredListCard {
                    SacredMenuRow(
                        icon: "square.and.pencil",
                        title: "Notes",
                        subtitle: notesSubtitle)
                }
            }
            .buttonStyle(.plain)

            PrivateFootnote()
        }
    }

    /// Compact preview of the current nickname for the menu-row subtitle.
    /// Falls back to a soft prompt when nothing is set so the row still
    /// telegraphs what tapping it does.
    private var nicknameSubtitle: String {
        let value = (connection?.nickname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty
            ? "Replaces their name on your end."
            : value
    }

    /// Single-line preview for notes — shows the first non-empty line,
    /// truncated; soft prompt when empty.
    private var notesSubtitle: String {
        let raw = (connection?.privateNotes ?? "")
        let firstLine = raw
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if firstLine.isEmpty { return "What you notice about them." }
        return firstLine.count <= 60 ? firstLine : String(firstLine.prefix(60)) + "…"
    }

    /// Tile-row that pushes to a dedicated full-screen page for media + files.
    /// Sits right below the About section so it reads as part of the
    /// "things you've stored about this person" cluster.
    private func mediaFilesRow(_ c: Connection) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            NavigationLink(destination: ConnectionAttachmentsScreen(connectionId: c.id)) {
                SacredListCard {
                    SacredMenuRow(icon: "photo.on.rectangle", title: "Media & Files")
                }
            }
            .buttonStyle(.plain)

            PrivateFootnote()
        }
    }

    /// Shared chat archive — every photo and voice note exchanged in
    /// the chat. Only renders when the connection is paired with an
    /// in-app friendship; for local Persons there's no chat to mine.
    @ViewBuilder
    private func chatMediaFilesRow(_ c: Connection) -> some View {
        if let friendshipId = c.friendshipId {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                NavigationLink(destination: ChatMediaFilesScreen(
                    friendshipId: friendshipId,
                    connectionDisplayName: c.displayLabel)
                ) {
                    SacredListCard {
                        SacredMenuRow(icon: "bubble.left.and.bubble.right", title: "Chat Media & Files")
                    }
                }
                .buttonStyle(.plain)

                SharedFootnote("Both of you can see this.")
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

    /// Quiet scaffold line that only renders when a section is empty —
    /// gives first-timers context without claiming real estate once
    /// they've populated the section.
    private func sectionScaffold(_ text: String) -> some View {
        Text(text)
            .font(.sacredMicro)
            .foregroundColor(.sacredMuted)
            .padding(.horizontal, 4)
    }

    // MARK: - Save flows

    private func seedDrafts(force: Bool = false) {
        guard let c = connection else { return }
        guard !didSeed || force else { return }
        circlesDraft = c.circles
        displayNameDraft = c.person.displayName
        phoneDraft = c.person.phoneNumber ?? ""
        emailDraft = c.person.email ?? ""
        cityDraft = c.person.city ?? ""
        stateDraft = c.person.state ?? ""
        countryDraft = c.person.country ?? ""
        didSeed = true
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
        target: ReminderEditTarget,
        label: String,
        date: String,
        recurrence: ReminderRecurrence
    ) async {
        guard let c = connection else { return }
        do {
            switch target {
            case .new:
                _ = try await ReminderRepository.shared.create(
                    label: label,
                    date: date,
                    recurrence: recurrence,
                    remindersEnabled: true,
                    connectionId: c.id)
            case .edit(let entry):
                _ = try await ReminderRepository.shared.update(
                    id: entry.id,
                    label: label,
                    date: date,
                    recurrence: recurrence)
            }
            saveError = nil
            dateEditTarget = nil
            await loadDates()
        } catch {
            saveError = "Couldn't save. Try again."
        }
    }

    private func deleteDate(target: ReminderEditTarget) async {
        guard case .edit(let entry) = target else { return }
        do {
            try await ReminderRepository.shared.delete(id: entry.id)
            saveError = nil
            dateEditTarget = nil
            await loadDates()
        } catch {
            saveError = "Couldn't delete. Try again."
        }
    }

    /// Fetch this connection's important dates from the new reminders endpoint.
    private func loadDates() async {
        datesLoading = true
        defer { datesLoading = false }
        do {
            dates = try await ReminderRepository.shared.list(connectionId: connectionId)
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Connection", "Failed to load dates: \(error)")
            }
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


private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Soft, blurred bloom of the connection's avatar painted behind the header.
/// Faded out via a radial mask so the warm sacred background still shows
/// through at the edges — the photo reads as ambient atmosphere, not a
/// second image.
/// Page-wide ambient wash derived from the connection's avatar — heavy
/// blur, low opacity, vertical gradient mask that fades out toward the
/// bottom so the page chrome at the bottom (Remove from circle, etc.)
/// stays calm. Sized to fill its container; pair with `.ignoresSafeArea()`
/// when used as a full-page background.
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
                    .blur(radius: 80)
                    .opacity(0.14)
                    .mask {
                        LinearGradient(
                            colors: [.black, .black.opacity(0.7), .clear],
                            startPoint: .top,
                            endPoint: .bottom)
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

/// Identifies which Connection-overlay editor is currently presented.
/// Mirrors the `AccountEdit` enum on Home so the per-Connection sheets
/// follow the same shape (title + presentation detent) the personal
/// account-edit flow uses.
enum ConnectionOverlayEdit: String, Identifiable {
    case nickname
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nickname: return "Nickname"
        case .notes:    return "Notes"
        }
    }

    var detent: PresentationDetent {
        switch self {
        case .nickname: return .height(380)
        case .notes:    return .large
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

