import SwiftUI

/// The Home tab's date label + greeting block. Centralized so the date
/// rhythm and serif greeting size live in one place.
struct SacredHomeHeader: View {
    let dateLabel: String
    let greeting: String

    var body: some View {
        VStack(spacing: SacredSpacing.xs) {
            Text(dateLabel)
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)
            Text(greeting)
                .font(.sacredGreeting)
                .foregroundColor(.sacredText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}
