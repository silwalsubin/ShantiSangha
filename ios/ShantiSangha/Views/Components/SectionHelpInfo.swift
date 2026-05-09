import SwiftUI

/// Small `info.circle` button that pops a quiet help bubble when
/// tapped. Lets section labels stay short while keeping the
/// scaffolding copy ("Tag this person with one or more circles…")
/// reachable for first-time users without claiming permanent
/// real estate under every card.
struct SectionHelpInfo: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.sacredMuted.opacity(0.7))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .top) {
            Text(text)
                .font(.sacredText)
                .foregroundColor(.sacredText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(SacredSpacing.m)
                .frame(maxWidth: 280)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("More info")
        .accessibilityHint("Shows what this section is for")
    }
}
