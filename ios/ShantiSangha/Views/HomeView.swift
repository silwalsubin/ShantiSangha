import SwiftUI
import FirebaseAuth
import WidgetKit

/// Home screen — daily dashboard with progress circles
struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @State private var showNewTask = false
    @State private var showRecurringSummary = false
    @State private var showMilestoneSummary = false
    @State private var mantra: String?
    @State private var showFAB = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    // Daily mantra
                    if let mantra {
                        Text(mantra)
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .italic()
                            .foregroundColor(.sacredTextSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                    }

                    // Greeting
                    Text(timeGreeting)
                        .font(.sacredTitle)
                        .foregroundColor(.sacredText)

                    // Evening nudge
                    if shouldShowNudge {
                        nudgeCard
                            .padding(.top, 16)
                            .padding(.horizontal, 16)
                    }

                    if vm.loading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if !vm.hasTasks {
                        emptyState
                    } else {
                        // Dashboard circles
                        HStack(spacing: 0) {
                            if vm.totalRecurring > 0 {
                                Button { showRecurringSummary = true } label: {
                                    progressCircle(
                                        label: "Practices",
                                        done: vm.doneRecurring,
                                        total: vm.totalRecurring,
                                        color: .sacredGold
                                    )
                                }
                                .frame(maxWidth: .infinity)
                            }

                            if vm.filteredTotal > 0 {
                                Button { showMilestoneSummary = true } label: {
                                    progressCircle(
                                        label: "Goals",
                                        done: vm.filteredDone,
                                        total: vm.filteredTotal,
                                        color: .sacredGoldDark,
                                        detail: vm.goalsSummaryDetail
                                    )
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 40)
                        .padding(.bottom, 20)

                        // All done message
                        if vm.allPracticesDone {
                            Text("All practices complete. You showed up today.")
                                .font(.sacredText)
                                .foregroundColor(.sacredTextSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 8)
                        }
                    }
                }
                .padding(.top, 32)
                .padding(.bottom, 100)
            }
            .background(Color.sacredBg.ignoresSafeArea())
            .refreshable {
                await vm.load()
                updateWidgetData()
            }
            .task {
                await vm.load()
                await loadMantra()
                updateWidgetData()
            }
            .onChange(of: vm.doneRecurring) { updateWidgetData() }
            .onChange(of: vm.doneMilestones) { updateWidgetData() }
            .onReceive(NotificationCenter.default.publisher(for: .silentPushReceived)) { _ in
                Task { await loadMantra() }
            }
            .onAppear { withAnimation(.easeOut(duration: 0.25)) { showFAB = true } }
            .onDisappear { showFAB = false }

            // FAB
            if showFAB {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showNewTask = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.sacredHeading)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .cymbalGold()
                        .clipShape(Circle())
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationDestination(isPresented: $showNewTask) {
            NewTaskView { title, type, targetDate in
                await vm.createTask(title: title, type: type, targetDate: targetDate)
            }
        }
        .navigationDestination(isPresented: $showRecurringSummary) {
            RecurringSummaryView(vm: vm)
        }
        .navigationDestination(isPresented: $showMilestoneSummary) {
            MilestoneSummaryView(vm: vm)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("You haven't set any practices yet.")
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)

            Button { showNewTask = true } label: {
                Text("Set your first practice")
                    .font(.sacredTextSemibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(LinearGradient.sacredGoldShiny)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Progress circle

    private func progressCircle(label: String, done: Int, total: Int, color: Color, detail: String? = nil) -> some View {
        let progress = total > 0 ? Double(done) / Double(total) : 0

        return VStack(spacing: 14) {
            ZStack {
                // Track
                Circle()
                    .stroke(Color.sacredMuted.opacity(0.12), lineWidth: 10)

                // Progress arc
                if done > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                colors: [color.opacity(0.7), color, color.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: progress)
                }

                // Count
                VStack(spacing: 2) {
                    if let detail = detail {
                        Text(detail)
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("\(done)")
                            .font(.system(size: 36, weight: .bold, design: .serif))
                            .foregroundColor(done > 0 ? color : .sacredMuted)
                        Text("of \(total)")
                            .font(.sacredCaption)
                            .foregroundColor(.sacredMuted)
                    }
                }
            }
            .frame(width: 130, height: 130)

            HStack(spacing: 6) {
                Image(systemName: label == "Practices" ? "arrow.triangle.2.circlepath" : "calendar.badge.clock")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
                Text(label)
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredTextSecondary)
            }
        }
    }

    // MARK: - Gentle nudge

    private static let nudgeMessages = [
        "Your practices are here when you're ready.",
        "No rush. Just a quiet reminder that you showed up by opening the app.",
        "Even a small step counts. What feels doable right now?",
        "The day isn't over yet. You're here — that matters.",
        "A moment of stillness is still a practice.",
        "You opened the app. That's the hardest part.",
        "Whatever you can do today is enough.",
    ]

    @State private var nudgeMessage = Self.nudgeMessages.randomElement()!

    private var shouldShowNudge: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 18 && !vm.loading && vm.totalRecurring > 0 && vm.doneRecurring == 0
    }

    private var nudgeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "leaf")
                .font(.sacredIcon)
                .foregroundColor(.sacredGold)
                .padding(.top, 2)

            Text(nudgeMessage)
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.sacredGold.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.sacredGold.opacity(0.1)))
        )
    }

    // MARK: - Widget data sync

    private func updateWidgetData() {
        let pending = vm.tasks.filter { $0.type == .oneTime && $0.completedAt == nil }
        WidgetData.update(
            mantra: mantra,
            practicesDone: vm.doneRecurring,
            practicesTotal: vm.totalRecurring,
            goalsOverdue: pending.filter { ($0.daysRemaining ?? 1) < 0 }.count,
            goalsDueToday: pending.filter { $0.daysRemaining == 0 }.count,
            userName: Auth.auth().currentUser?.displayName?.components(separatedBy: " ").first
        )
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Mantra

    private func loadMantra() async {
        do {
            let response: MantraResponse = try await ApiService.shared.get("/mantra/today")
            if let content = response.content, !content.isEmpty {
                mantra = content
                return
            }

            // Generation triggered — poll for result
            for _ in 1...5 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                let retry: MantraResponse = try await ApiService.shared.get("/mantra/today")
                if let content = retry.content, !content.isEmpty {
                    mantra = content
                    return
                }
            }
        } catch {}
    }

    // MARK: - Time greeting

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let firstName = Auth.auth().currentUser?.displayName?
            .components(separatedBy: " ").first
        let name = firstName.map { ", \($0)" } ?? ""
        if hour < 12 { return "Good morning\(name)" }
        if hour < 17 { return "Good afternoon\(name)" }
        return "Good evening\(name)"
    }
}

private struct MantraResponse: Decodable {
    let content: String?
}
