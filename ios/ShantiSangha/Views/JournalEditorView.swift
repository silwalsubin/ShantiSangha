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
                        // New entries open with the cursor here; return hands
                        // focus straight down into the writing so the optional
                        // title never blocks the page.
                        TextField("Title (optional)", text: $title)
                            .font(.sacredHeading)
                            .foregroundColor(.sacredText)
                            .focused($titleFocused)
                            .submitLabel(.next)
                            .onSubmit { contentFocused = true }
                            .typingHaptics(for: title)
                            .onChange(of: title) {
                                persistDraft()
                                debounceSave()
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
                                    .font(.sacredJournal)
                                    .foregroundColor(.sacredMuted)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            // scrollDisabled: the editor grows with its text so
                            // the page scrolls as ONE surface — no inner
                            // scroller fighting the outer one.
                            TextEditor(text: $content)
                                .font(.sacredJournal)
                                .foregroundColor(.sacredText)
                                .lineSpacing(6)
                                .scrollContentBackground(.hidden)
                                .scrollDisabled(true)
                                .frame(minHeight: 300)
                                .focused($contentFocused)
                                .typingHaptics(for: content)
                                .onChange(of: content) {
                                    persistDraft()
                                    debounceSave()
                                }
                        }
                    }
                    .padding(16)
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
            ToolbarItem(placement: .navigationBarTrailing) {
                if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                    ShareLink(item: shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }
                }
            }
        }
        // Save state floats quietly at the bottom center — above the keyboard
        // while writing, at the foot of the page when it's down.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !loading && !createFailed {
                saveLamp
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
            applyStoredDraftIfPresent()
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
