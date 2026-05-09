import SwiftUI

/// Bottom-sheet "pick one of N options" surface — title, short prompt, then
/// a `SacredListCard` of icon-titled rows with chevrons. Used wherever a
/// single tap needs to fan out to a small set of named alternatives
/// (begin-reflection, add-keepsake, etc.) — the sacred-design replacement
/// for `confirmationDialog`, which iOS 26 renders as a tail-anchored
/// popover that doesn't fit the rest of the chrome.
///
/// Each choice's `action` is responsible for any post-tap dismissal / state
/// update on the parent — this sheet does not auto-dismiss because some
/// callers chain straight into a follow-up sheet on the same presentation
/// pathway and need to control timing.
///
/// Default detent is 320pt; bump via `detentHeight` if a caller adds more
/// rows or a longer prompt.
struct SacredChoice: Identifiable {
    let id: String
    let icon: String
    let title: String
    let action: () -> Void

    init(id: String? = nil, icon: String, title: String, action: @escaping () -> Void) {
        self.id = id ?? "\(icon)|\(title)"
        self.icon = icon
        self.title = title
        self.action = action
    }
}

struct SacredChoiceSheet: View {
    let title: String
    let prompt: String
    let choices: [SacredChoice]
    var detentHeight: CGFloat = 320

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                SacredBackground()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    Text(prompt)
                        .font(.sacredText)
                        .foregroundColor(.sacredTextSecondary)
                        .lineSpacing(4)
                        .padding(.horizontal, 20)
                        .padding(.top, SacredSpacing.s)
                        .padding(.bottom, SacredSpacing.l)

                    SacredListCard {
                        VStack(spacing: 0) {
                            ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    choice.action()
                                } label: {
                                    SacredMenuRow(icon: choice.icon, title: choice.title)
                                }
                                .buttonStyle(.plain)
                                if index < choices.count - 1 {
                                    Divider().padding(.leading, 56)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.sacredTextMedium)
                        .foregroundColor(.sacredMuted)
                }
            }
        }
        .presentationDetents([.height(detentHeight)])
    }
}
