import SwiftUI

/// A single-row expandable disclosure — tap the header to reveal content
/// below it. Used throughout the chart surfaces ("What this means", "What the
/// icons mean", chart reading section rows).
///
/// The header is always `[optional leading icon] [title] [chevron]` with the
/// chevron snapped to the trailing edge. Light haptic fires on toggle.
///
/// Expansion is caller-owned via a `Binding<Bool>` so multiple disclosures
/// sharing a parent `Set<String>` stay independent of component instances.
/// Use `disclosureBinding(_:key:)` below to adapt a keyed set.
struct SacredDisclosure<Content: View>: View {
    enum TitleStyle {
        /// Uppercase section label — `.sacredSectionLabel`, tracking 2.
        case label
        /// Sentence-case body — `.sacredSmallSemibold`.
        case body
    }

    let title: String
    /// Optional replacement title shown when expanded (e.g. "Hide"). Nil keeps
    /// the same title in both states.
    let expandedTitle: String?
    /// SF Symbol name for the leading icon. Nil hides the slot entirely.
    let leadingIcon: String?
    let titleStyle: TitleStyle
    @Binding var isExpanded: Bool
    let content: () -> Content

    init(
        _ title: String,
        expandedTitle: String? = nil,
        leadingIcon: String? = nil,
        titleStyle: TitleStyle = .body,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.expandedTitle = expandedTitle
        self.leadingIcon = leadingIcon
        self.titleStyle = titleStyle
        self._isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let leadingIcon {
                Image(systemName: leadingIcon)
                    .font(.sacredMicro)
                    .foregroundColor(.sacredGold.opacity(0.7))
            }
            Group {
                switch titleStyle {
                case .label:
                    Text(displayTitle)
                        .font(.sacredSectionLabel)
                        .tracking(2)
                        .foregroundColor(.sacredLabel)
                case .body:
                    Text(displayTitle)
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.sacredText)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .bold, design: .serif))
                .foregroundColor(.sacredMuted.opacity(0.6))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var displayTitle: String {
        isExpanded ? (expandedTitle ?? title) : title
    }
}

/// Adapts a keyed `Set<String>` expansion store (the common pattern across
/// chart surfaces) into the `Binding<Bool>` that SacredDisclosure expects.
///
/// ```swift
/// @State private var expanded: Set<String> = []
/// ...
/// SacredDisclosure("Nakshatra", isExpanded: disclosureBinding($expanded, key: "nakshatra")) { ... }
/// ```
func disclosureBinding(_ set: Binding<Set<String>>, key: String) -> Binding<Bool> {
    Binding(
        get: { set.wrappedValue.contains(key) },
        set: { open in
            if open { set.wrappedValue.insert(key) }
            else { set.wrappedValue.remove(key) }
        }
    )
}
