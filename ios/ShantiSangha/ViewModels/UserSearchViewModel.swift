import Foundation
import SwiftUI

/// State holder for the user-search screen. Owns:
/// - the two text inputs (name + location), with debounced firing so we
///   don't hit the backend on every keystroke
/// - paginated results — append on `loadNext()`, replace on a new query
/// - loading / error state for the UI
///
/// The view drives this by binding `query` and `location`. Whenever either
/// changes, the VM cancels any in-flight request, waits 300 ms (so a fast
/// typist doesn't flood the backend), then fires page 1. Scrolling near the
/// end of the loaded set calls `loadNext()` which appends the next page.
@MainActor
final class UserSearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var location: String = ""
    @Published private(set) var results: [UserSearchResult] = []
    @Published private(set) var loading = false
    @Published private(set) var loadingMore = false
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var hasMore: Bool = false
    @Published private(set) var errorMessage: String?

    private var currentPage: Int = 0
    private let pageSize: Int = 20
    private var debounceTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?

    /// Has the user typed enough for a real search to fire? At least one of
    /// the two inputs must have a non-whitespace value — the backend rejects
    /// the call otherwise.
    var hasFilters: Bool {
        !trimmedQuery.isEmpty || !trimmedLocation.isEmpty
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLocation: String {
        location.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Call this from `.onChange(of: query)` and `.onChange(of: location)`.
    /// Debounces by 300 ms so a typing burst fires one request, not ten.
    func scheduleSearch() {
        debounceTask?.cancel()
        let snapshotQuery = trimmedQuery
        let snapshotLocation = trimmedLocation
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            guard let self else { return }
            await self.runSearch(query: snapshotQuery, location: snapshotLocation, page: 1, append: false)
        }
    }

    /// Trigger when the visible scroll list nears its end. No-op if there's
    /// nothing more, if a load is already in flight, or if filters are empty.
    func loadNext() {
        guard hasMore, !loading, !loadingMore, hasFilters else { return }
        let nextPage = currentPage + 1
        Task { [weak self] in
            guard let self else { return }
            await self.runSearch(query: trimmedQuery, location: trimmedLocation, page: nextPage, append: true)
        }
    }

    /// Wipe results and stop any in-flight request — used when the screen
    /// disappears or the user clears both inputs.
    func reset() {
        debounceTask?.cancel()
        fetchTask?.cancel()
        results = []
        currentPage = 0
        totalCount = 0
        hasMore = false
        errorMessage = nil
        loading = false
        loadingMore = false
    }

    // MARK: - Private

    private func runSearch(query: String, location: String, page: Int, append: Bool) async {
        // Empty filters → just clear and bail. The backend would 400; no
        // point in the round trip.
        if query.isEmpty && location.isEmpty {
            results = []
            currentPage = 0
            totalCount = 0
            hasMore = false
            errorMessage = nil
            return
        }

        fetchTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            if append {
                self.loadingMore = true
            } else {
                self.loading = true
            }
            defer {
                if append { self.loadingMore = false } else { self.loading = false }
            }
            do {
                let pageResult = try await UserSearchAPI.search(
                    query: query.isEmpty ? nil : query,
                    location: location.isEmpty ? nil : location,
                    page: page,
                    pageSize: self.pageSize)

                if append {
                    // Append, deduping by userId in case backend pages overlap
                    let existingIds = Set(self.results.map(\.userId))
                    let appended = pageResult.results.filter { !existingIds.contains($0.userId) }
                    self.results.append(contentsOf: appended)
                } else {
                    self.results = pageResult.results
                }
                self.currentPage = pageResult.page
                self.totalCount = pageResult.totalCount
                self.hasMore = pageResult.hasMore
                self.errorMessage = nil
            } catch {
                if !error.isCancellation {
                    self.errorMessage = self.friendlyMessage(for: error)
                }
            }
        }
        fetchTask = task
        await task.value
    }

    private func friendlyMessage(for error: Error) -> String {
        if let api = error as? ApiError, case .httpError(let code, _) = api {
            switch code {
            case 400: return "Type a name or a place to start searching."
            case 401: return "Your session expired. Please sign in again."
            case 429: return "You're searching too fast. Try again in a moment."
            default:  return "We couldn't reach the server. Try again."
            }
        }
        return error.localizedDescription
    }
}
