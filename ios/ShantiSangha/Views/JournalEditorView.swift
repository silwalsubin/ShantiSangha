import SwiftUI

/// Journal editor — write or edit a private reflection.
/// For new journals, nothing is created on the server until the user starts typing.
struct JournalEditorView: View {
    let journalId: String?
    let isNew: Bool

    @State private var activeId: String?
    @State private var title = ""
    @State private var content = ""
    @State private var loading = true
    @State private var saving = false
    @State private var lastSaved: Date?
    @State private var creating = false
    @Environment(\.dismiss) private var dismiss
    private let api = ApiService.shared

    // Auto-save debounce
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Title field
                        TextField("Title (optional)", text: $title)
                            .font(.sacredHeading)
                            .foregroundColor(.sacredText)
                            .onChange(of: title) { onEdit() }

                        // Content field
                        ZStack(alignment: .topLeading) {
                            if content.isEmpty {
                                Text("What's on your mind...")
                                    .font(.sacredText)
                                    .foregroundColor(.sacredMuted)
                                    .padding(.top, 8)
                            }

                            TextEditor(text: $content)
                                .font(.sacredText)
                                .foregroundColor(.sacredText)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 300)
                                .onChange(of: content) { onEdit() }
                        }
                    }
                    .padding(16)
                }

                // Status bar
                HStack {
                    if saving || creating {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(creating ? "Creating..." : "Saving...")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredMuted)
                        }
                    } else if let saved = lastSaved {
                        Text("Saved \(saved.formatted(.relative(presentation: .named)))")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.sacredBg)
            }
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle(isNew ? "New Entry" : "Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            if let id = journalId {
                activeId = id
                await loadJournal()
            }
            // For new journals: don't create anything yet — wait for first edit
            loading = false
        }
        .onDisappear {
            saveTask?.cancel()
            // Final save only if we have an entry with content
            if activeId != nil && !content.isEmpty {
                Task { await save() }
            }
        }
    }

    // MARK: - Edit handling

    private func onEdit() {
        if activeId == nil && isNew {
            // First edit on a new journal — create it now
            Task { await createAndSave() }
        } else {
            scheduleAutoSave()
        }
    }

    private func scheduleAutoSave() {
        guard activeId != nil else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s debounce
            if !Task.isCancelled {
                await save()
            }
        }
    }

    // MARK: - Network

    private func createAndSave() async {
        guard !creating else { return }
        creating = true
        do {
            let journal: JournalCreatedResponse = try await api.post("/journals", body: CreateJournalRequest(
                title: title.isEmpty ? "" : title,
                content: content
            ))
            activeId = journal.id
            lastSaved = Date()
        } catch {
            AppLogger.shared.error("Journal", "Failed to create journal: \(error)")
        }
        creating = false
        // Schedule a follow-up save in case content changed while creating
        scheduleAutoSave()
    }

    private func loadJournal() async {
        guard let id = activeId else { return }
        do {
            let journal: JournalDetailResponse = try await api.get("/journals/\(id)")
            title = journal.title ?? ""
            content = journal.content ?? ""
        } catch {
            AppLogger.shared.error("Journal", "Failed to load journal: \(error)")
        }
    }

    private func save() async {
        guard let id = activeId, !saving, !creating else { return }
        saving = true
        do {
            let _: EmptyResponse = try await api.patch("/journals/\(id)", body: UpdateJournalRequest(
                title: title.isEmpty ? nil : title,
                content: content
            ))
            lastSaved = Date()
        } catch {
            AppLogger.shared.error("Journal", "Failed to save journal: \(error)")
        }
        saving = false
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
