import SwiftUI

/// The gold-gradient primary action button used for commit moments across the
/// app ("Save", "Try again", "Use this place", "Set your first practice").
///
/// Two shapes cover every primary CTA in the codebase:
/// - `.pill` — capsule, compact, inline or centered (errors, empty states,
///    confirm inside a picker sheet).
/// - `.commit` — rounded-rectangle with shimmer, used for the big "commit
///   this sheet" moment at the bottom of NewTask / QuickAddGoal /
///   ChangeDueDate. Always full-width.
///
/// Light haptic fires on tap automatically. `isDisabled` dims the gradient
/// and blocks taps; `isLoading` replaces the label with a spinner.
struct SacredPrimaryButton: View {
    enum Style {
        case pill
        case commit
    }

    let title: String
    let icon: String?
    let style: Style
    let fullWidth: Bool
    let isDisabled: Bool
    let isLoading: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        style: Style = .pill,
        fullWidth: Bool = false,
        isDisabled: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        // `.commit` always fills width — it's the anchor of a sheet. Callers
        // of `.pill` opt in explicitly when they want a full-width capsule.
        self.fullWidth = style == .commit ? true : fullWidth
        self.isDisabled = isDisabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button {
            guard !isDisabled, !isLoading else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            label
                .foregroundColor(.white)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(background)
                .clipShape(shape)
                .opacity(isDisabled ? 0.55 : 1)
                .modifier(ShimmerIfCommit(active: style == .commit && !isDisabled))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
    }

    @ViewBuilder
    private var label: some View {
        if isLoading {
            ProgressView().tint(.white)
        } else if let icon {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.sacredSmallSemibold)
                Text(title)
                    .font(.sacredButtonLabel)
            }
        } else {
            Text(title)
                .font(.sacredButtonLabel)
        }
    }

    // MARK: - Style table

    private var horizontalPadding: CGFloat {
        switch style {
        case .pill: return 22
        case .commit: return 16
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .pill: return 12
        case .commit: return 14
        }
    }

    private var background: some View {
        switch style {
        case .pill: return AnyView(LinearGradient.sacredGoldShinyVertical)
        case .commit: return AnyView(LinearGradient.sacredGoldShiny)
        }
    }

    private var shape: AnyShape {
        switch style {
        case .pill: AnyShape(Capsule())
        case .commit: AnyShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

/// Applies `.shimmer()` only for the commit style — keeps the pill clean.
/// Pulled out so the conditional lives in one spot.
private struct ShimmerIfCommit: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content.shimmer()
        } else {
            content
        }
    }
}
