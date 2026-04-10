import SwiftUI

/// Shows a recorded voice note's transcript.
struct VoiceNoteDetailView: View {
    let entryId: String

    @State private var entry: VoiceEntryDetail?
    @State private var loading = true
    private let api = ApiService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let entry {
                    // Status
                    HStack(spacing: 8) {
                        Image(systemName: "mic")
                            .font(.sacredIcon)
                            .foregroundColor(.sacredGold)
                        Text(statusLabel(entry))
                            .font(.sacredTextSemibold)
                            .foregroundColor(.sacredText)
                        Spacer()
                        Text(formatDate(entry.createdAt))
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }

                    Divider()

                    // Transcript
                    if let transcript = entry.transcript, !transcript.isEmpty {
                        Text(transcript)
                            .font(.sacredText)
                            .foregroundColor(.sacredText)
                            .lineSpacing(6)
                    } else if entry.status == "Completed" {
                        Text("No transcript available.")
                            .font(.sacredText)
                            .foregroundColor(.sacredMuted)
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Transcribing your voice note...")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                } else {
                    Text("Could not load voice note.")
                        .font(.sacredText)
                        .foregroundColor(.sacredMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
            .padding(16)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle("Voice Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let transcript = entry?.transcript, !transcript.isEmpty {
                    ShareLink(item: transcript) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }
                }
            }
        }
        .task { await loadEntry() }
    }

    // MARK: - Helpers

    private func statusLabel(_ entry: VoiceEntryDetail) -> String {
        if entry.transcript != nil && !(entry.transcript?.isEmpty ?? true) {
            return "Transcribed"
        }
        switch entry.status {
        case "Completed": return "Transcribed"
        case "Transcribing": return "Transcribing..."
        case "Failed": return "Transcription failed"
        default: return "Processing..."
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return f.string(from: date)
    }

    // MARK: - Network

    private func loadEntry() async {
        do {
            entry = try await api.get("/voice/entries/\(entryId)")
        } catch {
            AppLogger.shared.error("VoiceDetail", "Failed to load entry: \(error)")
        }
        loading = false
    }
}

// MARK: - Model

struct VoiceEntryDetail: Decodable {
    let id: String
    let status: String
    let transcript: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, transcript, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "Pending"
        transcript = try c.decodeIfPresent(String.self, forKey: .transcript)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        if let dateStr = try c.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = iso.date(from: dateStr) ?? isoBasic.date(from: dateStr) ?? Date()
        } else {
            createdAt = Date()
        }
        if let dateStr = try c.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = iso.date(from: dateStr) ?? isoBasic.date(from: dateStr) ?? Date()
        } else {
            updatedAt = Date()
        }
    }
}
