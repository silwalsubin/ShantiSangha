import SwiftUI
import AVFoundation

/// Voice note recorder — speak when writing feels too heavy.
struct VoiceNoteView: View {
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var audioLevels: [CGFloat] = Array(repeating: 0.1, count: 40)
    @State private var uploading = false
    @State private var permissionDenied = false
    @State private var recordingURL: URL?
    @Environment(\.dismiss) private var dismiss
    private let api = ApiService.shared

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Duration
            Text(formatDuration(recordingDuration))
                .font(.sacredDisplayNumber)
                .foregroundColor(.sacredText)
                .monospacedDigit()

            // Waveform
            GeometryReader { geo in
                let barCount = audioLevels.count
                let totalSpacing = CGFloat(barCount - 1) * 3
                let barWidth = max(3, (geo.size.width - totalSpacing) / CGFloat(barCount))

                HStack(spacing: 3) {
                    ForEach(0..<barCount, id: \.self) { i in
                        RoundedRectangle(cornerRadius: barWidth / 2)
                            .fill(isRecording ? Color.sacredGold : Color.sacredMuted.opacity(0.3))
                            .frame(width: barWidth, height: max(4, audioLevels[i] * 60))
                            .animation(.easeOut(duration: 0.1), value: audioLevels[i])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 60)
            .padding(.horizontal, 24)

            // Status text
            Text(statusText)
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)

            Spacer()

            // Controls
            if uploading {
                ProgressView("Uploading...")
                    .font(.sacredText)
                    .foregroundColor(.sacredMuted)
            } else {
                HStack(spacing: 40) {
                    if isRecording {
                        // Cancel
                        Button {
                            cancelRecording()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.sacredHeading)
                                .foregroundColor(.sacredMuted)
                                .frame(width: 56, height: 56)
                                .background(Color.sacredBgCard)
                                .clipShape(Circle())
                        }

                        // Stop & save
                        Button {
                            Task { await stopAndUpload() }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.sacredHeading)
                                .foregroundColor(.white)
                                .frame(width: 64, height: 64)
                                .goldShine()
                                .clipShape(Circle())
                                .shadow(color: .sacredGold.opacity(0.3), radius: 8, y: 4)
                        }
                    } else {
                        // Record button
                        Button {
                            startRecording()
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "mic.fill")
                                    .font(.sacredHero)
                                    .foregroundColor(.white)
                                    .frame(width: 80, height: 80)
                                    .goldShine()
                                    .clipShape(Circle())
                                    .shadow(color: .sacredGold.opacity(0.3), radius: 12, y: 6)

                                Text("Tap to begin")
                                    .font(.sacredSmall)
                                    .foregroundColor(.sacredMuted)
                            }
                        }
                    }
                }
            }

            Spacer()
                .frame(height: 40)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle("Voice Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .alert("Microphone Access Required", isPresented: $permissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text("ShantiSangha needs microphone access to record voice notes. Please enable it in Settings.")
        }
        .onDisappear {
            timer?.invalidate()
            audioRecorder?.stop()
        }
    }

    // MARK: - State

    private var statusText: String {
        if uploading { return "Saving your reflection..." }
        if isRecording { return "Recording... speak freely" }
        return "Record a voice reflection"
    }

    // MARK: - Recording

    private func startRecording() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    beginRecording()
                } else {
                    permissionDenied = true
                }
            }
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            AppLogger.shared.error("Voice", "Failed to set audio session: \(error)")
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice_\(UUID().uuidString).m4a")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isRecording = true
            recordingDuration = 0

            // Update timer for duration + waveform
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                recordingDuration += 0.1
                audioRecorder?.updateMeters()
                let level = audioRecorder?.averagePower(forChannel: 0) ?? -160
                // Normalize: -160dB (silence) to 0dB (max) → 0.0 to 1.0
                let normalized = max(0, (level + 50) / 50)
                audioLevels.removeFirst()
                audioLevels.append(CGFloat(normalized))
            }

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            AppLogger.shared.error("Voice", "Failed to start recording: \(error)")
        }
    }

    private func cancelRecording() {
        timer?.invalidate()
        audioRecorder?.stop()
        isRecording = false
        recordingDuration = 0
        audioLevels = Array(repeating: 0.1, count: 40)

        // Clean up temp file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func stopAndUpload() async {
        timer?.invalidate()
        audioRecorder?.stop()
        isRecording = false
        uploading = true

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        guard let url = recordingURL else {
            uploading = false
            return
        }

        do {
            // Step 1: Get presigned upload URL
            let uploadInfo: UploadUrlResponse = try await api.post("/voice/upload-url", body: ["extension": "m4a"])

            // Step 2: Upload file to S3
            let fileData = try Data(contentsOf: url)
            var uploadRequest = URLRequest(url: URL(string: uploadInfo.uploadUrl)!)
            uploadRequest.httpMethod = "PUT"
            uploadRequest.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
            uploadRequest.httpBody = fileData

            let (_, response) = try await URLSession.shared.data(for: uploadRequest)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw ApiError.invalidResponse
            }

            // Step 3: Create voice entry in backend
            let _: VoiceEntryCreatedResponse = try await api.post("/voice/entries", body: ["objectKey": uploadInfo.objectKey])

            // Clean up temp file
            try? FileManager.default.removeItem(at: url)

            dismiss()
        } catch {
            AppLogger.shared.error("Voice", "Failed to upload voice note: \(error)")
            uploading = false
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Models

struct UploadUrlResponse: Decodable {
    let uploadUrl: String
    let objectKey: String
}

struct VoiceEntryCreatedResponse: Decodable {
    let id: String
    let status: String
}
