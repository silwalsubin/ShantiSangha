import SwiftUI

/// The Home tab's date stamp + greeting block. The date now uses the
/// same calendar tile as reminder rows so the visual vocabulary is
/// consistent across the app.
struct SacredHomeHeader: View {
    let greeting: String

    var body: some View {
        VStack(spacing: SacredSpacing.xs) {
            Text(dayOfWeek)
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)
            SacredDateStamp(date: Date(), isToday: true)
                .padding(.top, 2)
            Text(greeting)
                .font(.sacredGreeting)
                .foregroundColor(.sacredText)
                .multilineTextAlignment(.center)
                .padding(.top, SacredSpacing.s)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var dayOfWeek: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: Date()).uppercased()
    }
}
