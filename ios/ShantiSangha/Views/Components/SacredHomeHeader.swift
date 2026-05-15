import SwiftUI

/// The Home tab's date stamp + greeting block. The date now uses the
/// same calendar tile as reminder rows so the visual vocabulary is
/// consistent across the app.
struct SacredHomeHeader: View {
    let greeting: String
    var onDateTap: (() -> Void)? = nil
    @AppStorage("home.dateCalendarHintDismissed") private var hasDismissedDateCalendarHint = false
    @State private var dateCue = false
    @State private var hasShownDateCue = false

    var body: some View {
        VStack(spacing: SacredSpacing.xs) {
            dateEntry
            Text(greeting)
                .font(.sacredGreeting)
                .foregroundColor(.sacredText)
                .multilineTextAlignment(.center)
                .padding(.top, SacredSpacing.s)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var dateEntry: some View {
        if let onDateTap {
            Button {
                hasDismissedDateCalendarHint = true
                onDateTap()
            } label: {
                VStack(spacing: 6) {
                    tappableDateStamp

                    if !hasDismissedDateCalendarHint {
                        Text("Tap the date to see your month")
                            .font(.sacredMicro)
                            .foregroundColor(.sacredMuted.opacity(0.86))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: hasDismissedDateCalendarHint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open calendar")
            .accessibilityHint("Shows reminders by date")
            .onAppear(perform: pulseDateCueOnce)
        } else {
            SacredDateStamp(date: Date(), size: 60)
        }
    }

    private var tappableDateStamp: some View {
        SacredDateStamp(date: Date(), size: 60)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sacredGold.opacity(dateCue ? 0.36 : 0.14), lineWidth: 1)
            )
            .shadow(color: .sacredGold.opacity(dateCue ? 0.22 : 0.06), radius: dateCue ? 18 : 8, y: 4)
            .scaleEffect(dateCue ? 1.03 : 1)
            .frame(minWidth: 76, minHeight: 76)
            .contentShape(Rectangle())
    }

    private func pulseDateCueOnce() {
        guard !hasShownDateCue, !hasDismissedDateCalendarHint else { return }
        hasShownDateCue = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation(.easeInOut(duration: 0.45)) {
                dateCue = true
            }
            try? await Task.sleep(nanoseconds: 850_000_000)
            withAnimation(.easeInOut(duration: 0.5)) {
                dateCue = false
            }
        }
    }
}
