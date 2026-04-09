import SwiftUI

/// Journal editor — write or edit a private reflection.
struct JournalEditorView: View {
    let journalId: String
    let isNew: Bool

    @State private var title = ""
    @State private var content = ""
    @State private var loading = true
    @State private var saving = false
    @State private var lastSaved: Date?
    @Environment(\.dismiss) private var dismiss
    private let api = ApiService.shared

    // Auto-save debounce
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title field
                    TextField("Title (optional)", text: $title)
                        .font(.sacredHeading)
                        .foregroundColor(.sacredText)
                        .onChange(of: title) { scheduleAutoSave() }

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
                            .onChange(of: content) { scheduleAutoSave() }
                    }
                }
                .padding(16)
            }

            // Status bar
            HStack {
                if saving {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Saving...")
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
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle(isNew ? "New Entry" : "Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            if !isNew {
                await loadJournal()
            }
            loading = false
        }
        .onDisappear {
            saveTask?.cancel()
            // Final save on exit
            if !content.isEmpty {
                Task { await save() }
            }
        }
    }

    // MARK: - Auto-save

    private func scheduleAutoSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s debounce
            if !Task.isCancelled {
                await save()
            }
        }
    }

    // MARK: - Network

    private func loadJournal() async {
        do {
            let journal: JournalDetailResponse = try await api.get("/journals/\(journalId)")
            title = journal.title ?? ""
            content = journal.content ?? ""
        } catch {
            AppLogger.shared.error("Journal", "Failed to load journal: \(error)")
        }
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        do {
            let _: EmptyResponse = try await api.patch("/journals/\(journalId)", body: UpdateJournalRequest(
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
