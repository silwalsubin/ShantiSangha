import SwiftUI

/// Journal editor — write or edit a private reflection.
struct JournalEditorView: View {
    let journalId: String?
    let isNew: Bool

    @State private var serverId: String?
    @State private var title = ""
    @State private var content = ""
    @State private var loading = true
    @State private var saving = false
    @State private var saveFailed = false
    @State private var lastSaved: Date?
    @Environment(\.dismiss) private var dismiss
    private let api = ApiService.shared

    @State private var saveTask: Task<Void, Never>?

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
        VStack(spacing: 0) {
            if loading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("Title (optional)", text: $title)
                            .font(.sacredHeading)
                            .foregroundColor(.sacredText)
                            .onChange(of: title) { debounceSave() }

                        ZStack(alignment: .topLeading) {
                            if content.isEmpty {
                                Text(placeholder)
                                    .font(.sacredText)
                                    .foregroundColor(.sacredMuted)
                                    .padding(.top, 8)
                            }
                            TextEditor(text: $content)
                                .font(.sacredText)
                                .foregroundColor(.sacredText)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 300)
                                .onChange(of: content) { debounceSave() }
                        }
                    }
                    .padding(16)
                }

                // Status bar
                HStack {
                    if saving {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("Saving...").font(.sacredSmall).foregroundColor(.sacredMuted)
                        }
                    } else if saveFailed {
                        Text("Not saved")
                            .font(.sacredSmallSemibold).foregroundColor(.sacredRed)
                    } else if let saved = lastSaved {
                        Text("Saved \(saved.formatted(.relative(presentation: .named)))")
                            .font(.sacredSmall).foregroundColor(.sacredMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.sacredBg)
            }
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle(isNew ? "New Entry" : "Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
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
        .task { await setup() }
        .onDisappear {
            // Delete empty journals when user backs out without writing
            if let id = serverId, content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { try? await api.delete("/journals/\(id)") }
            }
        }
    }

    // MARK: - Setup

    private func setup() async {
        if let id = journalId {
            // Editing existing
            serverId = id
            await loadJournal()
        } else {
            // Create immediately — same pattern as conversations
            async let create: () = createJournal()
            async let prompt: () = fetchPrompt()
            _ = await (create, prompt)
        }
        loading = false
    }

    private func fetchPrompt() async {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        do {
            let response: JournalPromptResponse = try await api.get("/journal/prompt?date=\(df.string(from: Date()))")
            if let p = response.prompt, !p.isEmpty {
                placeholder = p
            }
        } catch {
            // Fall back to the static placeholder already set
        }
    }

    // MARK: - Share

    private var shareText: String {
        let heading = title.isEmpty ? "" : "\(title)\n\n"
        return "\(heading)\(content)"
    }

    // MARK: - Save

    private func debounceSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled { await save() }
        }
    }

    private func save() async {
        guard let id = serverId, !saving else { return }
        saving = true
        saveFailed = false
        do {
            let _: EmptyResponse = try await api.patch("/journals/\(id)", body: UpdateJournalRequest(
                title: title.isEmpty ? nil : title,
                content: content
            ))
            lastSaved = Date()
        } catch {
            saveFailed = true
            AppLogger.shared.error("Journal", "Failed to save: \(error)")
        }
        saving = false
    }

    // MARK: - Network

    private func createJournal() async {
        do {
            let journal: JournalCreatedResponse = try await api.post(
                "/journals", body: CreateJournalRequest(title: "Untitled", content: " "))
            serverId = journal.id
        } catch {
            AppLogger.shared.error("Journal", "Failed to create: \(error)")
        }
    }

    private func loadJournal() async {
        guard let id = serverId else { return }
        do {
            let journal: JournalDetailResponse = try await api.get("/journals/\(id)")
            title = journal.title ?? ""
            content = journal.content ?? ""
        } catch {
            AppLogger.shared.error("Journal", "Failed to load: \(error)")
        }
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
