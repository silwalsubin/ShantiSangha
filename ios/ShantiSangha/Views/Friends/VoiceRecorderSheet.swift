import SwiftUI
import AVFoundation

/// Compact bottom sheet for recording an outbound voice message.
/// On stop, hands the encoded audio + content type + duration to `onSend`.
struct VoiceRecorderSheet: View {
    let onSend: (Data, String, Int) -> Void

    @StateObject private var recorder = AudioRecorder()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: SacredSpacing.l) {
            Text("Voice message")
                .font(.sacredHeading)
                .foregroundColor(.sacredText)

            Text(durationLabel)
                .font(.sacredDisplayNumber)
                .foregroundColor(.sacredText)

            HStack(spacing: SacredSpacing.l) {
                Button { dismiss() } label: {
                    Text("Cancel")
                        .font(.sacredButtonLabel)
                        .foregroundColor(.sacredMuted)
                        .frame(width: 110, height: 48)
                        .background(Capsule().fill(Color.sacredBgCard))
                }

                Button { toggleRecording() } label: {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(recorder.isRecording ? Color.sacredRed : Color.sacredGold))
                }

                Button {
                    if let data = recorder.stop() {
                        onSend(data, "audio/m4a", recorder.durationMs)
                    }
                    dismiss()
                } label: {
                    Text("Send")
                        .font(.sacredButtonLabel)
                        .foregroundColor(.white)
                        .frame(width: 110, height: 48)
                        .background(Capsule().fill(LinearGradient.sacredGoldShinyVertical))
                }
                .disabled(!recorder.hasRecording)
            }

            if let err = recorder.errorMessage {
                Text(err)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredRed)
            }

            Spacer()
        }
        .padding(SacredSpacing.l)
        .presentationDetents([.height(360)])
        .background(Color.sacredBg.ignoresSafeArea())
        .onDisappear { recorder.cancel() }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            _ = recorder.stop()
        } else {
            recorder.start()
        }
    }

    private var durationLabel: String {
        let total = recorder.durationMs / 1000
        return String(format: "%01d:%02d", total / 60, total % 60)
    }
}

@MainActor
final class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var durationMs = 0
    @Published var errorMessage: String?
    @Published var hasRecording = false

    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private var timer: Timer?
    private var fileURL: URL?

    func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try session.setActive(true)
            session.requestRecordPermission { _ in }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22050,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.record()
            recorder = r
            fileURL = url
            startedAt = Date()
            isRecording = true
            durationMs = 0
            hasRecording = false
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let start = self.startedAt else { return }
                    self.durationMs = Int(Date().timeIntervalSince(start) * 1000)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() -> Data? {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        hasRecording = true
        return data
    }

    func cancel() {
        if isRecording { _ = stop() }
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
        hasRecording = false
        durationMs = 0
    }
}
