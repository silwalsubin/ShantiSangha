import SwiftUI
import AVFoundation
import Accelerate

/// Shows a recorded voice note's transcript with audio playback.
struct VoiceNoteDetailView: View {
    let entryId: String

    @State private var entry: VoiceEntryDetail?
    @State private var loading = true
    @State private var retrying = false
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
                    } else if entry.status == "Failed" {
                        VStack(spacing: 16) {
                            Text("Transcription failed.")
                                .font(.sacredText)
                                .foregroundColor(.sacredMuted)
                            Button {
                                Task { await retryTranscription() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry")
                                }
                                .font(.sacredSmallSemibold)
                                .foregroundColor(.sacredGold)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .stroke(Color.sacredGold.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .disabled(retrying)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
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
        VStack(spacing: 12) {
            // Waveform + play button
            HStack(spacing: 14) {
                Button {
                    if player.isPlaying { player.pause() } else { player.play(url: url) }
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.sacredGold)
                        .frame(width: 44, height: 44)
                }

                // Waveform
                WaveformView(
                    samples: player.waveformSamples,
                    progress: player.progress,
                    onSeek: { pct in player.seek(to: pct) }
                )
                .frame(height: 48)
            }

            // Time labels
            HStack {
                Text(player.timeLabel)
                    .font(.sacredMicro)
                    .foregroundColor(.sacredGold)
                    .monospacedDigit()
                Spacer()
                Text(player.durationLabel)
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.sacredGold.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 16)
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

    private func retryTranscription() async {
        retrying = true
        do {
            let _: EmptyResponse = try await api.post("/voice/entries/\(entryId)/retry")
            // Reload to show the "Transcribing..." state
            await loadEntry()
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("VoiceDetail", "Failed to retry transcription: \(error)")
            }
        }
        retrying = false
    }
}

// MARK: - Waveform View

/// Draws audio waveform bars — played portion in gold with motion shine,
/// remaining in muted. Tap/drag to seek.
struct WaveformView: View {
    let samples: [Float]
    let progress: CGFloat
    var onSeek: ((CGFloat) -> Void)?
    @ObservedObject private var motion = MotionManager.shared

    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            let count = samples.isEmpty ? 0 : samples.count
            let step = barWidth + barSpacing
            let visibleBars = min(count, Int(geo.size.width / step))
            let barSamples = downsample(to: visibleBars)
            // Shine center mapped from device tilt (0...1 across the waveform)
            let shineCenter = (1 + motion.shineX) / 2

            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0..<visibleBars, id: \.self) { i in
                    let amplitude = CGFloat(barSamples[i])
                    let barHeight = max(3, amplitude * geo.size.height * 0.9)
                    let played = visibleBars > 0 && CGFloat(i) / CGFloat(visibleBars) <= progress
                    let barPosition = visibleBars > 1 ? CGFloat(i) / CGFloat(visibleBars - 1) : 0.5

                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(played ? barColor(at: barPosition, shineCenter: shineCenter) : Color.sacredMuted.opacity(0.25))
                        .frame(width: barWidth, height: barHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let pct = max(0, min(1, value.location.x / geo.size.width))
                        onSeek?(pct)
                    }
            )
        }
    }

    /// Gold bar with a bright spot near the shine center
    private func barColor(at position: CGFloat, shineCenter: CGFloat) -> Color {
        let dist = abs(position - shineCenter)
        if dist < 0.06 {
            return Color.white.opacity(0.9)
        } else if dist < 0.15 {
            return Color.sacredGoldShine
        } else {
            return Color.sacredGold
        }
    }

    private func downsample(to count: Int) -> [Float] {
        guard count > 0, !samples.isEmpty else { return [] }
        if samples.count <= count { return samples }
        let chunkSize = Double(samples.count) / Double(count)
        return (0..<count).map { i in
            let start = Int(Double(i) * chunkSize)
            let end = min(Int(Double(i + 1) * chunkSize), samples.count)
            guard start < end else { return 0 }
            let slice = samples[start..<end]
            return slice.max() ?? 0
        }
    }
}

// MARK: - Audio Player Model

@MainActor
class AudioPlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var progress: CGFloat = 0
    @Published var timeLabel = "0:00"
    @Published var durationLabel = "0:00"
    @Published var waveformSamples: [Float] = []

    private var audioPlayer: AVPlayer?
    private var timeObserver: Any?
    private var currentUrl: URL?
    private var duration: Double = 0

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

        // Extract waveform in background
        Task.detached {
            let samples = await WaveformExtractor.extract(from: url, barCount: 80)
            await MainActor.run { [weak self] in
                self?.waveformSamples = samples
            }
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.audioPlayer = player

        // Observe time
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self,
                  let dur = player.currentItem?.duration,
                  dur.seconds.isFinite && dur.seconds > 0 else { return }
            Task { @MainActor in
                self.duration = dur.seconds
                self.progress = CGFloat(time.seconds / dur.seconds)
                self.timeLabel = self.formatTime(time.seconds)
                self.durationLabel = self.formatTime(dur.seconds)
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

    func seek(to pct: CGFloat) {
        guard let player = audioPlayer, duration > 0 else { return }
        let target = CMTime(seconds: Double(pct) * duration, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        progress = pct
        timeLabel = formatTime(Double(pct) * duration)
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
        durationLabel = "0:00"
        waveformSamples = []
        duration = 0
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Waveform Extractor

/// Extracts normalized amplitude samples from an audio file for visualization.
enum WaveformExtractor {
    static func extract(from url: URL, barCount: Int) async -> [Float] {
        do {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
                return placeholderSamples(barCount)
            }

            let formatDescriptions = try await track.load(.formatDescriptions)
            guard let desc = formatDescriptions.first else {
                return placeholderSamples(barCount)
            }
            _ = CMAudioFormatDescriptionGetStreamBasicDescription(desc)

            let reader = try AVAssetReader(asset: asset)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            reader.add(output)
            reader.startReading()

            // Read all samples
            var allSamples: [Int16] = []
            while let buffer = output.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(buffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(count: length)
                data.withUnsafeMutableBytes { ptr in
                    _ = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
                }
                let int16Samples = data.withUnsafeBytes { buf in
                    Array(buf.bindMemory(to: Int16.self))
                }
                allSamples.append(contentsOf: int16Samples)
            }

            guard !allSamples.isEmpty else { return placeholderSamples(barCount) }

            // Downsample to barCount buckets — take RMS of each chunk
            let chunkSize = max(1, allSamples.count / barCount)
            var bars: [Float] = []
            for i in 0..<barCount {
                let start = i * chunkSize
                let end = min(start + chunkSize, allSamples.count)
                guard start < end else { bars.append(0); continue }

                var sum: Float = 0
                for j in start..<end {
                    let val = Float(allSamples[j]) / Float(Int16.max)
                    sum += val * val
                }
                let rms = sqrt(sum / Float(end - start))
                bars.append(rms)
            }

            // Normalize to 0...1
            let maxVal = bars.max() ?? 1
            guard maxVal > 0 else { return placeholderSamples(barCount) }
            return bars.map { min(1, $0 / maxVal) }
        } catch {
            return placeholderSamples(barCount)
        }
    }

    /// Gentle sine-wave placeholder while loading
    private static func placeholderSamples(_ count: Int) -> [Float] {
        (0..<count).map { i in
            let t = Float(i) / Float(count)
            return 0.3 + 0.2 * sin(t * .pi * 4)
        }
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
