import SwiftUI
import AVFoundation

/// Shows a recorded voice note's transcript with audio playback.
struct VoiceNoteDetailView: View {
    let entryId: String

    @State private var entry: VoiceEntryDetail?
    @State private var loading = true
    @StateObject private var player = AudioPlayerModel()
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

                    // Audio player
                    if let audioUrl = entry.audioUrl, let url = URL(string: audioUrl) {
                        audioPlayerBar(url: url)
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
        .onDisappear { player.stop() }
    }

    // MARK: - Audio Player Bar

    private func audioPlayerBar(url: URL) -> some View {
        HStack(spacing: 16) {
            Button {
                if player.isPlaying { player.pause() } else { player.play(url: url) }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.sacredGold)
                    .frame(width: 44, height: 44)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.sacredMuted.opacity(0.15))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.sacredGold)
                        .frame(width: geo.size.width * player.progress, height: 4)
                }
            }
            .frame(height: 4)

            Text(player.timeLabel)
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.sacredGold.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sacredGold.opacity(0.12)))
        )
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
            if !error.isCancellation {
                AppLogger.shared.error("VoiceDetail", "Failed to load entry: \(error)")
            }
        }
        loading = false
    }
}

// MARK: - Audio Player Model

@MainActor
class AudioPlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var progress: CGFloat = 0
    @Published var timeLabel = "0:00"

    private var audioPlayer: AVPlayer?
    private var timeObserver: Any?
    private var currentUrl: URL?

    func play(url: URL) {
        // If same URL, just resume
        if url == currentUrl, let player = audioPlayer {
            player.play()
            isPlaying = true
            return
        }

        // New URL — set up player
        stop()
        currentUrl = url

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.audioPlayer = player

        // Observe time
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self,
                  let duration = player.currentItem?.duration,
                  duration.seconds.isFinite && duration.seconds > 0 else { return }
            Task { @MainActor in
                self.progress = CGFloat(time.seconds / duration.seconds)
                self.timeLabel = self.formatTime(time.seconds)
            }
        }

        // Observe end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.progress = 0
                self?.audioPlayer?.seek(to: .zero)
                self?.timeLabel = "0:00"
            }
        }

        // Configure audio session for playback
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        player.play()
        isPlaying = true
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
    }

    func stop() {
        audioPlayer?.pause()
        if let observer = timeObserver {
            audioPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        audioPlayer = nil
        currentUrl = nil
        isPlaying = false
        progress = 0
        timeLabel = "0:00"
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Model

struct VoiceEntryDetail: Decodable {
    let id: String
    let status: String
    let transcript: String?
    let audioUrl: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, transcript, audioUrl, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "Pending"
        transcript = try c.decodeIfPresent(String.self, forKey: .transcript)
        audioUrl = try c.decodeIfPresent(String.self, forKey: .audioUrl)

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
