import SwiftUI
import UIKit

/// Sacred chat composer — the bottom input bar shared between the AI
/// chat (`ChatView`) and friend chat (`FriendChatView`).
///
/// Provides the text field + send button at minimum, plus optional
/// slots:
///   - `accessories`: leading buttons before the field (photo, mic).
///     Pass `EmptyView()` to omit.
///   - `banner`: a row above the input (reply preview, edit banner).
///     Pass `EmptyView()` to omit.
///
/// The send icon switches to a checkmark when `isEditing` is true so the
/// same component handles the friend chat's edit-in-place flow.
struct SacredChatComposer<Banner: View, Accessories: View>: View {
    @Binding var text: String
    var placeholder: String = "Message"
    var isEditing: Bool = false
    var canSend: Bool
    var onSend: () -> Void
    /// Fired when the inner text field's focus changes. The friend chat
    /// uses this to scroll the latest message above the keyboard rise.
    var onFocusChange: ((Bool) -> Void)? = nil
    @ViewBuilder var accessories: () -> Accessories
    @ViewBuilder var banner: () -> Banner

    @FocusState private var focused: Bool

    /// Full init exposing both slots. Convenience inits below cover the
    /// no-banner / no-accessories cases.
    init(
        text: Binding<String>,
        placeholder: String = "Message",
        isEditing: Bool = false,
        canSend: Bool,
        onSend: @escaping () -> Void,
        onFocusChange: ((Bool) -> Void)? = nil,
        @ViewBuilder accessories: @escaping () -> Accessories,
        @ViewBuilder banner: @escaping () -> Banner
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isEditing = isEditing
        self.canSend = canSend
        self.onSend = onSend
        self.onFocusChange = onFocusChange
        self.accessories = accessories
        self.banner = banner
    }

    var body: some View {
        VStack(spacing: 6) {
            banner()

            HStack(alignment: .bottom, spacing: 8) {
                accessories()

                TextField(placeholder, text: $text, axis: .vertical)
                    .font(.sacredText)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.sacredBgCard))
                    .focused($focused)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSend()
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(canSend ? .sacredGold : .sacredMutedLight)
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, SacredSpacing.m)
        .padding(.vertical, SacredSpacing.s)
        .background(Color.sacredBg)
        .overlay(
            Rectangle()
                .fill(Color.sacredGold.opacity(0.1))
                .frame(height: 0.5),
            alignment: .top)
        .onChange(of: focused) { _, new in onFocusChange?(new) }
    }
}

// MARK: - Convenience inits

extension SacredChatComposer where Banner == EmptyView, Accessories == EmptyView {
    /// Plain composer — just text field + send button. Used by the AI
    /// chat which has no media buttons or reply/edit banners.
    init(
        text: Binding<String>,
        placeholder: String = "Message",
        canSend: Bool,
        onSend: @escaping () -> Void,
        onFocusChange: ((Bool) -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.canSend = canSend
        self.onSend = onSend
        self.onFocusChange = onFocusChange
        self.accessories = { EmptyView() }
        self.banner = { EmptyView() }
    }
}
