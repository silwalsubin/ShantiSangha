import SwiftUI

/// Transient banner for non-fatal feedback — a failed save, a refresh that
/// couldn't reach the server, a "copied to clipboard" confirmation. Never
/// shows raw error strings; the caller provides warm copy.
///
/// Usage:
/// ```swift
/// @State private var toastMessage: String?
/// ...
/// .sacredToast($toastMessage)           // error tone (default)
/// .sacredToast($toastMessage, tone: .success)
/// ```
/// The modifier auto-dismisses after 3.5s. Callers don't clear it manually.
struct SacredToast: View {
    enum Tone {
        case error
        case success
        case info
    }

    let message: String
    let tone: Tone

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.sacredSmall)
                .foregroundColor(accentColor)
            Text(message)
                .font(.sacredSmall)
                .foregroundColor(.sacredText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.sacredBgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accentColor.opacity(0.25), lineWidth: 1))
        .shadow(color: .sacredMuted.opacity(0.15), radius: 8, y: 4)
    }

    private var iconName: String {
        switch tone {
        case .error: return "exclamationmark.circle"
        case .success: return "checkmark.circle"
        case .info: return "info.circle"
        }
    }

    private var accentColor: Color {
        switch tone {
        case .error: return .sacredRed
        case .success: return .sacredGreen
        case .info: return .sacredGold
        }
    }
}

// MARK: - View modifier

extension View {
    /// Attaches a toast to the top of this view. When `message` becomes
    /// non-nil the toast slides in; after ~3.5s it auto-dismisses back to
    /// nil. Callers pass a Binding so they can also clear it early (e.g.
    /// when the user navigates away).
    func sacredToast(
        _ message: Binding<String?>,
        tone: SacredToast.Tone = .error
    ) -> some View {
        modifier(SacredToastModifier(message: message, tone: tone))
    }
}

private struct SacredToastModifier: ViewModifier {
    @Binding var message: String?
    let tone: SacredToast.Tone

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let text = message {
                    SacredToast(message: text, tone: tone)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: message) { _, newValue in
                guard newValue != nil else { return }
                // Auto-dismiss — the caller doesn't need to schedule a timer.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    withAnimation(.easeOut(duration: 0.3)) { message = nil }
                }
            }
            .animation(.easeIn(duration: 0.2), value: message)
    }
}
