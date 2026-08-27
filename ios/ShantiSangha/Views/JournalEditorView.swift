import SwiftUI
import Pow

/// Journal editor — write or edit a private reflection.
struct JournalEditorView: View {
    let journalId: String?
    let isNew: Bool
    let initialContent: String?
    /// Reports each successful save (id, title, content) so the presenting
    /// list can reflect edits without waiting on a refetch.
    let onSaved: ((String, String, String) -> Void)?

    @State private var serverId: String?
    @State private var title = ""
    @State private var content = ""
    @State private var loading = true
    @State private var spinnerVisible = false
    @State private var saving = false
    @State private var saveFailed = false
    @State private var createFailed = false
    @State private var lastSaved: Date?
    @State private var hasUnsavedChanges = false
    // Snapshot of what the server holds. onChange fires for programmatic
    // assignments too (loading the entry, applying a draft), so saves are
    // gated on a real difference — opening a journal must not re-save it.
    @State private var savedTitle = ""
    @State private var savedContent = ""
    @Environment(\.dismiss) private var dismiss
    private let api = ApiService.shared

    @State private var saveTask: Task<Void, Never>?
    @FocusState private var titleFocused: Bool
    @FocusState private var contentFocused: Bool

    /// Memory-drawn opening question. Unlike the placeholder it stays visible
    /// while writing — the invitation shouldn't vanish at the first keystroke.
    @State private var promptText: String?

    /// The page's date line — the entry's creation day for existing
    /// journals, today for new ones.
    @State private var entryDate = Date()

    /// Kindle-style reading size: one Aa tap cycles three page sizes.
    /// A display preference shared by every entry — never per-text
    /// formatting, so the page stays one calm surface.
    @AppStorage("journal.textSize") private var textSizeStep = 1

    // MARK: Undo history
    //
    // Snapshot-based undo/redo over (title, content). Keystrokes are
    // coalesced into bursts: a snapshot commits after a short pause in
    // typing, so undo steps back by thought, not by character. History
    // ignores programmatic assignments (loading, draft recovery, applying
    // undo itself) because those set `lastCommitted` to match the text.
    private struct HistorySnapshot: Equatable {
        let title: String
        let content: String
    }
    @State private var undoStack: [HistorySnapshot] = []
    @State private var redoStack: [HistorySnapshot] = []
    @State private var lastCommitted = HistorySnapshot(title: "", content: "")
    @State private var historyTask: Task<Void, Never>?

    init(journalId: String?, isNew: Bool, initialContent: String? = nil, onSaved: ((String, String, String) -> Void)? = nil) {
        self.journalId = journalId
        self.isNew = isNew
        self.initialContent = initialContent
        self.onSaved = onSaved
    }

    private static let placeholders = [
        "What felt true today...",
        "What are you grateful for...",
        "What did you notice about yourself today...",
        "What made you smile today...",
        "What are you learning right now...",
        "What moment stood out today...",
        "What is on your heart...",
    ]
    @State private var placeholder = placeholders.randomElement()!

    var body: some View {
        // The editor is presented as a fullScreenCover — it slides up OVER the
        // tab bar and reveals it on the way down, so the bar never pops in
        // abruptly (SwiftUI can't animate `.toolbar(.hidden, for: .tabBar)`
        // restores on pop). Own NavigationStack carries the nav bar.
        NavigationStack { editorContent }
            // Paint the presentation layer itself parchment so nothing
            // system-colored can peek through at the edges mid-slide.
            .presentationBackground(Color.sacredBg)
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            if loading {
                // No spinner flash during the cover transition — the page
                // arrives as calm parchment, and the wheel only fades in if
                // the load is genuinely slow.
                Spacer()
                ProgressView()
                    .opacity(spinnerVisible ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: spinnerVisible)
                    .task {
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        spinnerVisible = true
                    }
                Spacer()
            } else if createFailed {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.sacredHero)
                        .foregroundColor(.sacredRed)
                    Text("This entry could not be opened.")
                        .font(.sacredTextSemibold)
                        .foregroundColor(.sacredText)
                    Text("Your private space is still here. Try once more when the connection settles.")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    SacredPrimaryButton("Try again", icon: "arrow.clockwise") {
                        Task { await retryCreate() }
                    }
                }
                .padding(.horizontal, 32)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            // New entries open with the cursor here; return
                            // hands focus straight down into the writing so
                            // the optional title never blocks the page.
                            TextField("Title (optional)", text: $title)
                                .font(.sacredHeading)
                                .foregroundColor(.sacredText)
                                .tint(.sacredGold)
                                .focused($titleFocused)
                                .submitLabel(.next)
                                .onSubmit { contentFocused = true }
                                .typingHaptics(for: title)
                                .onChange(of: title) {
                                    persistDraft()
                                    debounceSave()
                                    recordHistory()
                                }

                            // A quiet dateline and hairline, like the opening
                            // of a chapter — the page knows its own day.
                            Text(dateLine)
                                .font(.sacredMicro)
                                .tracking(1.5)
                                .foregroundColor(.sacredLabel)
                            Rectangle()
                                .fill(Color.sacredGold.opacity(0.35))
                                .frame(width: 44, height: 1)
                        }

                        // The companion's question stays with the page while
                        // writing, like a note pinned above the paper.
                        if let promptText {
                            Text(promptText)
                                .font(.sacredSmall.italic())
                                .foregroundColor(.sacredMuted)
                                .lineSpacing(4)
                                .transition(.opacity)
                        }

                        ZStack(alignment: .topLeading) {
                            if content.isEmpty {
                                Text(placeholder)
                                    .font(pageFont)
                                    .foregroundColor(.sacredMuted)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            // scrollDisabled: the editor grows with its text so
                            // the page scrolls as ONE surface — no inner
                            // scroller fighting the outer one.
                            TextEditor(text: $content)
                                .font(pageFont)
                                .foregroundColor(.sacredText)
                                .tint(.sacredGold)
                                .lineSpacing(pageLineSpacing)
                                .scrollContentBackground(.hidden)
                                .scrollDisabled(true)
                                .frame(minHeight: 300)
                                .focused($contentFocused)
                                .typingHaptics(for: content)
                                .onChange(of: content) { oldValue, newValue in
                                    continueListIfNeeded(from: oldValue, to: newValue)
                                    persistDraft()
                                    debounceSave()
                                    recordHistory()
                                }
                        }
                    }
                    // Book margins: a touch wider than the app's default so
                    // the text column reads like a printed page.
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                // No indicator flash when loaded text resizes the content —
                // and bare parchment suits the page anyway.
                .scrollIndicators(.hidden)
                .transition(.opacity)

            }
        }
        .sacredBackground()
        .navigationTitle(isNew ? "New Entry" : "Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                }
                .accessibilityLabel("Close")
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // The Kindle "Aa": one tap steps the page through three
                // reading sizes — the text itself is the feedback.
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.25)) {
                        textSizeStep = (textSizeStep + 1) % 3
                    }
                } label: {
                    Text("Aa")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundColor(.sacredMuted)
                        .frame(width: 34, height: 44)
                }
                .accessibilityLabel("Reading size")

                if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                    ShareLink(item: shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }
                }
            }

            // Undo / redo ride above the keyboard while writing — present
            // when needed, gone when the pen is down.
            ToolbarItemGroup(placement: .keyboard) {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.sacredText)
                        .foregroundColor(canUndo ? .sacredGold : .sacredMuted.opacity(0.4))
                        .frame(width: 44, height: 44)
                }
                .disabled(!canUndo)
                .accessibilityLabel("Undo")

                Button(action: redo) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.sacredText)
                        .foregroundColor(canRedo ? .sacredGold : .sacredMuted.opacity(0.4))
                        .frame(width: 44, height: 44)
                }
                .disabled(!canRedo)
                .accessibilityLabel("Redo")

                Spacer()

                Button {
                    titleFocused = false
                    contentFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.sacredText)
                        .foregroundColor(.sacredMuted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Put the keyboard away")
            }
        }
        // The page's footer: the save lamp with the word count tucked
        // beneath it — one small centered column of quiet facts.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !loading && !createFailed {
                VStack(spacing: 3) {
                    saveLamp
                    if !wordCountText.isEmpty {
                        Text(wordCountText)
                            .font(.sacredMicro)
                            .foregroundColor(.sacredMuted)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .task { await setup() }
        .onDisappear {
            // Delete empty journals when user backs out without writing
            if let id = serverId, content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { try? await api.delete("/journals/\(id)") }
            } else {
                // Don't let the 1s debounce outlive the page — flush any
                // pending edits so the list behind us sees them.
                flushPendingSave()
            }
        }
    }

    // MARK: - Save lamp

    /// Wordless save state, in the universal vocabulary: a gold checkmark =
    /// saved (each save pulses a soft glow), dimmed while a save is in
    /// flight, cloud-with-slash = held on this device only, syncs when the
    /// connection settles. SF Symbols so it matches the share icon's weight.
    private var saveLamp: some View {
        Image(systemName: saveFailed ? "icloud.slash" : "checkmark.circle")
            .font(.sacredSmall)
            .foregroundColor(saveFailed ? .sacredMuted : .sacredGold)
            .opacity(saving ? 0.35 : 1)
            .animation(.easeOut(duration: 0.5), value: saving)
            .animation(.easeOut(duration: 0.5), value: saveFailed)
            .changeEffect(.glow(color: .sacredGold, radius: 10), value: lastSaved)
            .accessibilityLabel(
                saving ? "Saving" :
                saveFailed ? "Held on this device, not yet synced" :
                lastSaved != nil ? "Saved" : "Not yet saved")
    }

    // MARK: - Setup

    private func setup() async {
        createFailed = false
        if let id = journalId {
            // Editing existing — the words fade onto the page rather than pop.
            serverId = id
            await loadJournal()
            withAnimation(.easeOut(duration: 0.3)) {
                loading = false
            }
        } else {
            // Writing must never wait on the network: paint the editor and
            // raise the keyboard immediately; create the server row and fetch
            // the prompt in the background. Until the row exists, every
            // keystroke is held by the local draft.
            if let initialContent, !initialContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, content.isEmpty {
                content = initialContent
            }
            if content.isEmpty {
                // Recover words from a session that died before its server
                // row was created.
                applyStoredDraftIfPresent()
            }
            // History starts from whatever the page opened with.
            lastCommitted = currentSnapshot
            loading = false
            titleFocused = true

            async let create: () = createJournal()
            async let prompt: () = fetchPrompt()
            _ = await (create, prompt)

            // The row now exists — sync anything typed while it was creating.
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                persistDraft()
                debounceSave()
            }
        }
    }

    private func fetchPrompt() async {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        do {
            let response: JournalPromptResponse = try await api.get("/journal/prompt?date=\(df.string(from: Date()))")
            if let p = response.prompt, !p.isEmpty {
                withAnimation(.easeIn(duration: 0.3)) {
                    promptText = p
                }
            }
        } catch {
            // Quietly keep the static placeholder
        }
    }

    // MARK: - Share

    private var shareText: String {
        let heading = title.isEmpty ? "" : "\(title)\n\n"
        return "\(heading)\(content)"
    }

    // MARK: - Reading size

    /// Three page sizes, Kindle-fashion. Line spacing grows with the type
    /// so the page keeps its airy set at every step.
    private var pageFont: Font {
        let sizes: [CGFloat] = [15, 17, 20]
        return Font.system(size: sizes[textSizeStep % 3], design: .serif)
    }

    private var pageLineSpacing: CGFloat {
        let spacing: [CGFloat] = [7, 8, 10]
        return spacing[textSizeStep % 3]
    }

    // MARK: - Smart lists

    /// Plain-text list intelligence: pressing return at the end of the
    /// page continues a `- ` / `• ` / `* ` / `1. ` line with the next
    /// marker, and return on an empty marker ends the list. The words
    /// stay plain text — no formats, no toolbar, nothing to learn.
    /// End-of-page only: SwiftUI's TextEditor doesn't expose the caret,
    /// and appending is the one edit whose caret lands correctly.
    private func continueListIfNeeded(from oldValue: String, to newValue: String) {
        guard newValue.count == oldValue.count + 1,
              newValue.hasSuffix("\n"),
              newValue.dropLast() == oldValue else { return }

        let lastLine = String(oldValue.split(separator: "\n", omittingEmptySubsequences: false).last ?? "")

        for marker in ["- ", "• ", "* "] {
            if lastLine == marker {
                // Empty item — the list is finished; lift the marker away.
                content = String(oldValue.dropLast(marker.count)) + "\n"
                return
            }
            if lastLine.hasPrefix(marker) {
                content = newValue + marker
                return
            }
        }

        // Numbered lines: "3. next thought" → the return brings "4. ".
        if let dot = lastLine.firstIndex(of: "."),
           let number = Int(lastLine[..<dot]),
           lastLine[lastLine.index(after: dot)...].hasPrefix(" ") {
            let prefixLength = lastLine.distance(from: lastLine.startIndex, to: dot) + 2
            if lastLine.count == prefixLength {
                content = String(oldValue.dropLast(prefixLength)) + "\n"
            } else {
                content = newValue + "\(number + 1). "
            }
        }
    }

    // MARK: - Page furniture

    private var dateLine: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: entryDate).uppercased()
    }

    private var wordCount: Int {
        content.split(whereSeparator: \.isWhitespace).count
    }

    private var wordCountText: String {
        switch wordCount {
        case 0: return ""
        case 1: return "1 word"
        default: return "\(wordCount) words"
        }
    }

    // MARK: - Undo history

    private var currentSnapshot: HistorySnapshot {
        HistorySnapshot(title: title, content: content)
    }

    /// A burst of typing is still open — text differs from the last
    /// committed snapshot — so undo has somewhere to go even before the
    /// pause commits it.
    private var canUndo: Bool {
        !undoStack.isEmpty || currentSnapshot != lastCommitted
    }

    private var canRedo: Bool {
        !redoStack.isEmpty
    }

    /// Called from the text onChange handlers. Programmatic assignments
    /// (load, draft recovery, undo/redo application) keep `lastCommitted`
    /// equal to the text, so only real typing opens a burst.
    private func recordHistory() {
        historyTask?.cancel()
        guard currentSnapshot != lastCommitted else { return }
        // New writing forfeits the forward path — standard editor law.
        redoStack.removeAll()
        historyTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            commitBurst()
        }
    }

    private func commitBurst() {
        guard currentSnapshot != lastCommitted else { return }
        undoStack.append(lastCommitted)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        lastCommitted = currentSnapshot
    }

    private func undo() {
        historyTask?.cancel()
        commitBurst()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot)
        apply(previous)
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        historyTask?.cancel()
        undoStack.append(currentSnapshot)
        apply(next)
    }

    /// Restore a snapshot. Setting `lastCommitted` first keeps the change
    /// out of history; the onChange handlers still persist + save it.
    private func apply(_ snapshot: HistorySnapshot) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        lastCommitted = snapshot
        title = snapshot.title
        content = snapshot.content
    }

    // MARK: - Save

    private func debounceSave() {
        guard title != savedTitle || content != savedContent else { return }
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled { await save() }
        }
    }

    /// Cancel the debounce and save immediately (waiting out any in-flight
    /// save so the newest words win). Called when the editor is dismissed.
    private func flushPendingSave() {
        guard hasUnsavedChanges, serverId != nil else { return }
        saveTask?.cancel()
        saveTask = Task {
            while saving { try? await Task.sleep(nanoseconds: 100_000_000) }
            if hasUnsavedChanges { await save() }
        }
    }

    private func save() async {
        guard let id = serverId, !saving else {
            saveFailed = true
            return
        }
        saving = true
        saveFailed = false
        let sentTitle = title
        let sentContent = content
        do {
            let _: EmptyResponse = try await api.patch("/journals/\(id)", body: UpdateJournalRequest(
                title: sentTitle.isEmpty ? nil : sentTitle,
                content: sentContent
            ))
            lastSaved = Date()
            savedTitle = sentTitle
            savedContent = sentContent
            // Keystrokes during the round-trip stay pending for the next save.
            hasUnsavedChanges = title != sentTitle || content != sentContent
            clearDraft()
            onSaved?(id, sentTitle, sentContent)
        } catch {
            if !error.isCancellation {
                saveFailed = true
                AppLogger.shared.error("Journal", "Failed to save: \(error)")
            }
        }
        saving = false
    }

    // MARK: - Network

    private func createJournal() async {
        do {
            let journal: JournalCreatedResponse = try await api.post(
                "/journals", body: CreateJournalRequest(title: "Untitled", content: " "))
            serverId = journal.id
            createFailed = false
            applyStoredDraftIfPresent()
        } catch {
            if !error.isCancellation {
                createFailed = true
                AppLogger.shared.error("Journal", "Failed to create: \(error)")
            }
        }
    }

    private func retryCreate() async {
        loading = true
        await createJournal()
        loading = false
    }

    private func loadJournal() async {
        guard let id = serverId else { return }
        do {
            let journal: JournalDetailResponse = try await api.get("/journals/\(id)")
            title = journal.title ?? ""
            content = journal.content ?? ""
            savedTitle = title
            savedContent = content
            if let created = journal.createdAt {
                entryDate = created
            }
            applyStoredDraftIfPresent()
            // History starts from what the page opened with (draft included).
            lastCommitted = currentSnapshot
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Journal", "Failed to load: \(error)")
            }
        }
    }

    private static let pendingDraftKey = "journal.draft.pending"

    private var draftKey: String? {
        if let serverId { return "journal.draft.\(serverId)" }
        // New entry whose server row hasn't been created yet — keystrokes are
        // held under a pending key so nothing is lost even if the app dies
        // before the create round-trip completes.
        return isNew ? Self.pendingDraftKey : nil
    }

    private func persistDraft() {
        guard let key = draftKey else { return }
        let draft = JournalDraft(title: title, content: content)
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func applyStoredDraftIfPresent() {
        guard let key = draftKey,
              let data = UserDefaults.standard.data(forKey: key),
              let draft = try? JSONDecoder().decode(JournalDraft.self, from: data) else { return }

        if draft.title != title || draft.content != content {
            title = draft.title
            content = draft.content
            saveFailed = true
        }
    }

    private func clearDraft() {
        if let key = draftKey {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.removeObject(forKey: Self.pendingDraftKey)
    }
}

// MARK: - Models

struct JournalDetailResponse: Decodable {
    let id: String
    let title: String?
    let content: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, content, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        content = try c.decodeIfPresent(String.self, forKey: .content)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]
        if let raw = try c.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = iso.date(from: raw) ?? isoBasic.date(from: raw)
        } else {
            createdAt = nil
        }
    }
}

struct UpdateJournalRequest: Encodable {
    let title: String?
    let content: String?
}

struct JournalPromptResponse: Decodable {
    let prompt: String?
}

private struct JournalDraft: Codable {
    let title: String
    let content: String
}
