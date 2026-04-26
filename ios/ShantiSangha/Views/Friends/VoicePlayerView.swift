import SwiftUI
import AVFoundation

/// Inline voice-message playback control for chat bubbles. Plays from
/// the on-disk media cache when a copy is available (instant, works
/// offline); falls back to streaming the presigned S3 URL otherwise.
struct VoicePlayerView: View {
    let messageId: UUID
    let url: String?
    let durationMs: Int?
    let fromFriend: Bool

    @StateObject private var player = AudioStreamPlayer()

    var body: some View {
        HStack(spacing: 8) {
            Button { Task { await toggle() } } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundColor(fromFriend ? .sacredGold : .white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Voice message")
                    .font(.sacredSmallSemibold)
                    .foregroundColor(fromFriend ? .sacredText : .white)
                Text(durationLabel)
                    .font(.sacredMicro)
                    .foregroundColor(fromFriend ? .sacredMuted : .white.opacity(0.85))
            }
        }
    }

    private func toggle() async {
        if player.isPlaying { player.pause(); return }
        guard let urlStr = url, let remote = URL(string: urlStr) else { return }
        // Prefer cached local file — also primes the cache the first
        // time the user plays a voice message they've never opened.
        let playable = await ChatMediaCache.shared.cachedURL(
            messageId: messageId, remoteUrl: remote) ?? remote
        player.play(url: playable)
    }

    private var durationLabel: String {
        let totalMs = max(durationMs ?? 0, 0)
        let secs = totalMs / 1000
        return String(format: "%01d:%02d", secs / 60, secs % 60)
    }
}

@MainActor
final class AudioStreamPlayer: ObservableObject {
    @Published var isPlaying = false

    private var player: AVPlayer?
    private var observer: NSObjectProtocol?

    func play(url: URL) {
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isPlaying = false }
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        p.play()
        player = p
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
