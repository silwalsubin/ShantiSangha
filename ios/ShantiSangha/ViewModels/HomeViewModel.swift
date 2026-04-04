import Foundation
import Combine

/// ViewModel for the Home screen — "What needs your attention today?"
/// Delegates to TaskRepository for offline-first data management.
enum CommitmentFilter: String, CaseIterable {
    case week = "1W"
    case twoWeeks = "2W"
    case month = "1M"
    case all = "All"

    var maxDays: Int? {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .month: return 30
        case .all: return nil
        }
    }
}

@MainActor
class HomeViewModel: ObservableObject {
    @Published var loading = true
    @Published var commitmentFilter: CommitmentFilter = .week
    private let repo = TaskRepository.shared
    private var cancellables = Set<AnyCancellable>()

    var tasks: [AppTask] { repo.tasks }
    var hasTasks: Bool { !tasks.isEmpty }

    /// Pending recurring tasks
    var pendingRecurring: [AppTask] {
        tasks.filter { !$0.checkedIn && $0.type == .recurring }
    }

    /// Filtered commitments, sorted by urgency (overdue first, then nearest due)
    var filteredCommitments: [AppTask] {
        let maxDays = commitmentFilter.maxDays
        return tasks.filter {
            guard !$0.checkedIn && $0.type == .oneTime else { return false }
            if let max = maxDays {
                return ($0.daysRemaining ?? 999) <= max
            }
            return true
        }.sorted { ($0.daysRemaining ?? 0) < ($1.daysRemaining ?? 0) }
    }

    /// All milestones (for summary view)
    var allMilestones: [AppTask] {
        tasks.filter { $0.type == .oneTime }
    }
    var pendingMilestones: [AppTask] {
        allMilestones.filter { !$0.checkedIn }
            .sorted { ($0.daysRemaining ?? 999) < ($1.daysRemaining ?? 999) }
    }
    var completedMilestones: [AppTask] {
        allMilestones.filter { $0.checkedIn && $0.completedToday == true }
    }
    var overdueMilestones: Int {
        pendingMilestones.filter { ($0.daysRemaining ?? 1) <= 0 }.count
    }
    var totalMilestones: Int { allMilestones.count }
    var doneMilestones: Int { completedMilestones.count }

    // Filter-aware counts for progress ring
    private func milestonesInWindow(_ filter: CommitmentFilter) -> [AppTask] {
        allMilestones.filter { task in
            guard let max = filter.maxDays else { return true }
            return (task.daysRemaining ?? 999) <= max
        }
    }
    var filteredTotal: Int { milestonesInWindow(commitmentFilter).count }
    var filteredDone: Int { milestonesInWindow(commitmentFilter).filter { $0.checkedIn && $0.completedToday == true }.count }
    var filteredOverdue: Bool { milestonesInWindow(commitmentFilter).contains { !$0.checkedIn && ($0.daysRemaining ?? 1) <= 0 } }

    var pendingTasks: [AppTask] { pendingRecurring + filteredCommitments }

    var completedTasks: [AppTask] { tasks.filter { $0.checkedIn && $0.completedToday == true } }
    var skippedTasks: [AppTask] { tasks.filter { $0.checkedIn && $0.completedToday == false } }

    // Daily progress — recurring tasks only
    var totalRecurring: Int { tasks.filter { $0.type == .recurring }.count }
    var doneRecurring: Int { tasks.filter { $0.type == .recurring && $0.checkedIn }.count }

    init() {
        // Forward repo changes to trigger view updates
        repo.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        repo.$loading
            .receive(on: DispatchQueue.main)
            .assign(to: &$loading)
    }

    func load() async {
        await repo.refreshFromServer()
    }

    func checkIn(id: String, completed: Bool) async {
        await repo.checkIn(id: id, completed: completed)
    }

    func undoCheckIn(id: String) async {
        await repo.undoCheckIn(id: id)
    }

    func updateProgress(id: String, value: Int) async {
        await repo.updateProgress(id: id, value: value)
    }

    func deleteTask(id: String) async {
        await repo.deleteTask(id: id)
    }

    func updateDueDate(id: String, date: String) async {
        await repo.updateDueDate(id: id, date: date)
    }

    func createTask(title: String, type: TaskType, targetDate: String? = nil) async {
        await repo.createTask(title: title, type: type, targetDate: targetDate)
    }
}
