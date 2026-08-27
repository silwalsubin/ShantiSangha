import SwiftUI
import UIKit

/// The app-wide typing feel: a soft pulse per keystroke, quieter than the
/// `.light` taps used on buttons. Calm app: every page should feel like
/// paper that acknowledges the pen — and it should feel the same on every
/// field, from a journal entry to a search box.
///
/// Attach to any `TextField` / `TextEditor` with the field's bound text:
///
///     TextField("Title", text: $title)
///         .typingHaptics(for: title)
///
/// Fires on insertions only (deleting is silent) and at most once per
/// 0.06s so fast typing reads as a gentle texture, not a buzz.
extension View {
    func typingHaptics(for text: String) -> some View {
        modifier(TypingHapticsModifier(text: text))
    }
}

private struct TypingHapticsModifier: ViewModifier {
    let text: String
    @State private var lastPulse = Date.distantPast

    /// One shared generator so every field taps the motor with the same
    /// touch, and stays warm across fields.
    private static let generator = UIImpactFeedbackGenerator(style: .soft)

    func body(content: Content) -> some View {
        content.onChange(of: text) { oldValue, newValue in
            guard newValue.count > oldValue.count,
                  Date().timeIntervalSince(lastPulse) > 0.06 else { return }
            Self.generator.impactOccurred(intensity: 0.35)
            lastPulse = Date()
        }
    }
}
