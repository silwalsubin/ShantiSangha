import SwiftUI

/// Row for a recurring practice — title, streak heatbeat, swipe-to-complete.
struct PracticeRow: View {
    let practice: Practice
    let onDone: () -> Void
    let onSkip: () -> Void
    let onUndo: () -> Void
    let onDelete: () -> Void
    var activeSwipeId: Binding<String?>?

    /// Message shown on swipe-right — acknowledges the streak.
    private var checkinMessage: String {
        let nextStreak = practice.currentStreak + 1
        if nextStreak == 7 { return "Day 7 — one full week" }
        if nextStreak == 14 { return "Day 14 — two weeks strong" }
        if nextStreak == 30 { return "Day 30 — a whole month" }
        if nextStreak == 60 { return "Day 60 — remarkable" }
        if nextStreak == 100 { return "Day 100" }
        if nextStreak == 365 { return "Day 365 — one year" }
        if nextStreak >= 3 { return "Day \(nextStreak)" }
        return "Done"
    }

    @State private var offset: CGFloat = 0
    @State private var activeSwipe: SwipeDirection? = nil
    @State private var navigateToDetail = false

    private var swipeActive: Bool {
        activeSwipeId?.wrappedValue == practice.id
    }
    private let swipeThreshold: CGFloat = 80

    private enum SwipeDirection {
        case left, right
    }

    var body: some View {
        ZStack {
            if offset > 0 {
                HStack {
                    Image(systemName: "checkmark")
                        .font(.sacredTextSemibold)
                        .foregroundColor(.white)
                    Text(checkinMessage)
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.leading, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredGreen))
            } else if offset < 0 {
                HStack {
                    Spacer()
                    Text("Skip")
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.white)
                    Image(systemName: "moon.fill")
                        .font(.sacredSmall)
                        .foregroundColor(.white)
                }
                .padding(.trailing, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredMuted))
            }

            content
                .onTapGesture {
                    if activeSwipe == nil {
                        navigateToDetail = true
                    }
                }
                .offset(x: offset)
                .gesture(
                    !practice.checkedIn && !practice.saving
                    ? LongPressGesture(minimumDuration: 0.3)
                        .onEnded { _ in
                            activeSwipeId?.wrappedValue = practice.id
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        .sequenced(before:
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard swipeActive else { return }
                                    offset = value.translation.width
                                    if offset > swipeThreshold {
                                        activeSwipe = .right
                                    } else if offset < -swipeThreshold {
                                        activeSwipe = .left
                                    } else {
                                        activeSwipe = nil
                                    }
                                }
                                .onEnded { _ in
                                    if let swipe = activeSwipe {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            offset = swipe == .right ? 300 : -300
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                            if swipe == .right { onDone() } else { onSkip() }
                                            offset = 0
                                            activeSwipe = nil
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.3)) {
                                            offset = 0
                                        }
                                    }
                                    activeSwipeId?.wrappedValue = nil
                                }
                        )
                    : nil
                )
        }
        .navigationDestination(isPresented: $navigateToDetail) {
            PracticeDetailView(practiceId: practice.id)
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.sacredText)
                .foregroundColor(.sacredGold)
                .frame(width: 24, height: 24)

            Text(practice.title)
                .font(.sacredTextMedium)
                .foregroundColor(.sacredText)

            Spacer()

            HeatDotsView(streak: practice.currentStreak)
                .padding(.trailing, 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Group {
                if swipeActive {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.sacredBgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.sacredMuted.opacity(0.12), lineWidth: 1)
                        )
                }
            }
        )
    }
}

// MARK: - Heartbeat — 7-day streak as ECG-style pulse line

private struct HeatDotsView: View {
    let streak: Int

    private let width: CGFloat = 56
    private let height: CGFloat = 20
    private let days = 7

    @State private var trimEnd: CGFloat = 0

    var body: some View {
        HeartbeatShape(streak: streak, days: days)
            .trim(from: 0, to: trimEnd)
            .stroke(
                LinearGradient(
                    colors: [Color.sacredGold.opacity(0.3), Color.sacredGold],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 1.5
            )
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                    trimEnd = 1
                }
            }
    }
}

private struct HeartbeatShape: Shape {
    let streak: Int
    let days: Int

    func path(in rect: CGRect) -> Path {
        let stepX = rect.width / CGFloat(days - 1)
        let baseline = rect.height * 0.7
        let peakHeight = rect.height * 0.55

        var path = Path()
        path.move(to: CGPoint(x: 0, y: baseline))

        for day in 0..<days {
            let daysAgo = (days - 1) - day
            let isLit = daysAgo < streak
            let x = CGFloat(day) * stepX

            if isLit {
                let riseStart = x - stepX * 0.25
                let fallEnd = x + stepX * 0.25
                path.addLine(to: CGPoint(x: max(riseStart, 0), y: baseline))
                path.addQuadCurve(
                    to: CGPoint(x: min(fallEnd, rect.width), y: baseline),
                    control: CGPoint(x: x, y: baseline - peakHeight)
                )
            } else {
                path.addLine(to: CGPoint(x: x, y: baseline))
            }
        }

        return path
    }
}
