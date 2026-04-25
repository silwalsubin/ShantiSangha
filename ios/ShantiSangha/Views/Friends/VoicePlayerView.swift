import SwiftUI
import AVFoundation

/// Inline voice-message playback control for chat bubbles. Streams audio
/// directly from the presigned S3 URL provided by the backend.
struct VoicePlayerView: View {
    let url: String?
    let durationMs: Int?
    let fromFriend: Bool

    @StateObject private var player = AudioStreamPlayer()

    var body: some View {
        HStack(spacing: 8) {
            Button { toggle() } label: {
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

    private func toggle() {
        guard let url = url, let parsed = URL(string: url) else { return }
        if player.isPlaying { player.pause() } else { player.play(url: parsed) }
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
