import SwiftUI

/// Sacred chat bubble — the pill that wraps a single message body.
///
/// Two surfaces in the app render conversational bubbles:
///   - `ChatView`         (AI chat / chart reading)
///   - `FriendChatView`   (1:1 chat with a friend)
///
/// They share the same visual vocabulary: outgoing on the right with the
/// gold-shine gradient, incoming on the left in `sacredBgCard`. This view
/// owns that vocabulary so changes in one place propagate everywhere.
///
/// `SacredChatBubblePill` is just the pill (background, foreground,
/// padding, clip). The friend chat already wraps its own row that adds
/// avatar gutters, reply previews, reactions, and read receipts — it
/// passes a `SacredChatBubblePill` as the inner bubble. Screens that
/// don't need that extra chrome (chart chat) compose with
/// `SacredChatBubbleRow`, which adds the side-aligned spacer for free.
/// Which side of the conversation a message sits on.
///   - `.mine`   — the user's own message (right, gold gradient)
///   - `.theirs` — the AI assistant or another person (left, sacred bg card)
enum SacredChatSide {
    case mine
    case theirs
}

struct SacredChatBubblePill<Content: View>: View {
    let side: SacredChatSide
    let hasTail: Bool
    @ViewBuilder var content: () -> Content

    init(
        side: SacredChatSide,
        hasTail: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.side = side
        self.hasTail = hasTail
        self.content = content
    }

    var body: some View {
        content()
            .font(.sacredText)
            .foregroundColor(side == .mine ? .white : .sacredText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(background)
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 18,
                        bottomLeading: side == .theirs && hasTail ? 6 : 18,
                        bottomTrailing: side == .mine && hasTail ? 6 : 18,
                        topTrailing: 18),
                    style: .continuous)
            )
    }

    @ViewBuilder
    private var background: some View {
        if side == .mine {
            LinearGradient.sacredGoldShinyVertical
        } else {
            Color.sacredBgCard
        }
    }
}

/// Pill + side-aligned spacer in one. Drop-in for screens that don't need
/// the heavier composition (avatar gutter, reactions, reply preview).
struct SacredChatBubbleRow<Content: View>: View {
    let side: SacredChatSide
    let hasTail: Bool
    @ViewBuilder var content: () -> Content

    init(
        side: SacredChatSide,
        hasTail: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.side = side
        self.hasTail = hasTail
        self.content = content
    }

    var body: some View {
        HStack {
            if side == .mine { Spacer(minLength: 32) }
            SacredChatBubblePill(side: side, hasTail: hasTail, content: content)
            if side == .theirs { Spacer(minLength: 32) }
        }
    }
}
