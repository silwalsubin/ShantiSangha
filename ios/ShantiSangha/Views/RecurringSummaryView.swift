import SwiftUI

/// Shows all recurring practices for today — pending, completed, and skipped
struct RecurringSummaryView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var activeSwipeId: String?

    private var pending: [Practice] { vm.pendingPractices }
    private var completed: [Practice] { vm.completedPractices }
    private var skipped: [Practice] { vm.skippedPractices }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if vm.practices.isEmpty {
                    emptyState
                }

                if !pending.isEmpty {
                    sectionLabel("ACTIVE")
                    practiceList(pending)
                }

                if !completed.isEmpty {
                    sectionLabel("DONE")
                    practiceList(completed)
                }

                if !skipped.isEmpty {
                    sectionLabel("SKIPPED")
                    practiceList(skipped)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .sacredBackground()
        .navigationTitle("Practices")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 40)
            Image(systemName: "leaf.fill")
                .font(.system(size: 34))
                .foregroundColor(.sacredGreen)
            Text("No practices waiting.")
                .font(.sacredTextSemibold)
                .foregroundColor(.sacredText)
            Text("Return to Home when you are ready to begin again.")
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionLabel(_ label: String) -> some View {
        Text(label)
            .font(.sacredSectionLabel)
            .tracking(3)
            .foregroundColor(.sacredLabel)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    private func practiceList(_ practices: [Practice]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(practices.enumerated()), id: \.element.id) { index, practice in
                PracticeRow(
                    practice: practice,
                    onDone: { Task { await vm.checkIn(id: practice.id, completed: true) } },
                    onSkip: { Task { await vm.checkIn(id: practice.id, completed: false) } },
                    onUndo: { Task { await vm.undoCheckIn(id: practice.id) } },
                    onDelete: { Task { await vm.deletePractice(id: practice.id) } },
                    activeSwipeId: $activeSwipeId
                )

                if index < practices.count - 1 {
                    Divider()
                        .padding(.leading, 52)
                        .padding(.trailing, 16)
                }
            }
        }
    }
}
