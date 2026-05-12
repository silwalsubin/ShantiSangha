import SwiftUI

/// The Home tab's date stamp + greeting block. The date now uses the
/// same calendar tile as reminder rows so the visual vocabulary is
/// consistent across the app.
struct SacredHomeHeader: View {
    let greeting: String

    var body: some View {
        VStack(spacing: SacredSpacing.xs) {
            SacredDateStamp(date: Date(), isToday: true, size: 60)
            Text(greeting)
                .font(.sacredGreeting)
                .foregroundColor(.sacredText)
                .multilineTextAlignment(.center)
                .padding(.top, SacredSpacing.s)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}
