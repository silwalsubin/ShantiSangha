import SwiftUI

/// Floating action button — gold motion-reactive shine, white SF Symbol,
/// 56×56 circle. Anchor it with `.padding(.trailing, ...)` /
/// `.padding(.bottom, ...)` from the outer layout.
struct SacredFAB: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.sacredHeading)
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .goldShine()
                .clipShape(Circle())
        }
    }
}
