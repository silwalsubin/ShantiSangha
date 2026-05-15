import SwiftUI

/// Press-and-hold mic button. Mirrors the send button's `.circle.fill`
/// SF Symbol style + point size so the two buttons read as a matched
/// pair when placed side by side.
///
/// Each press replaces `text` with a fresh dictation — same behavior as
/// Apple's system dictation (Notes, Siri). Whatever was in the field
/// (typed or from a previous dictation) is wiped on press-down so the
/// new utterance lands cleanly.
///
/// `onComplete` fires after the recognizer stops, after `text` has been
/// updated with the final transcript — used by the Home pill to open
/// the assistant sheet with the dictated text pre-filled.
struct SacredVoiceInputButton: View {
    @Binding var text: String
    var size: CGFloat = 30
    var onComplete: (() -> Void)? = nil

    @StateObject private var recognizer = AssistantVoiceRecognizer()
    @State private var isHolding: Bool = false
    @State private var showAlert: Bool = false

    var body: some View {
        Image(systemName: recognizer.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
            .font(.system(size: size))
            .foregroundColor(recognizer.isRecording ? .sacredGold : .sacredMutedLight)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isHolding else { return }
                        isHolding = true
                        text = ""
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await recognizer.start() }
                    }
                    .onEnded { _ in
                        isHolding = false
                        recognizer.stop()
                        onComplete?()
                    }
            )
            .onChange(of: recognizer.transcript) { _, transcript in
                guard isHolding || recognizer.isRecording else { return }
                text = transcript
            }
            .onChange(of: recognizer.errorMessage) { _, msg in
                if msg != nil { showAlert = true }
            }
            .alert("Voice input", isPresented: $showAlert, presenting: recognizer.errorMessage) { _ in
                Button("OK", role: .cancel) { recognizer.errorMessage = nil }
            } message: { msg in
                Text(msg)
            }
            .onDisappear { recognizer.stop() }
    }
}
