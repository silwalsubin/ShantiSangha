# iOS Offline-First Architecture

## Core Principle

**The local database is the source of truth, not the API.**

The app reads from local storage always and syncs with the server in the background. The user never waits for a network call to see their data or perform actions.

## Data Flow

### Reading data
```
App Launch / Tab Switch
  → Read from SwiftData (instant)
  → Show UI immediately
  → Fetch from API in background
  → Update SwiftData
  → UI auto-updates via @Query / @Published
```

### Writing data (check-in, create task, delete, etc.)
```
User Action
  → Write to SwiftData (instant)
  → Show updated UI immediately
  → Queue API call in SyncService
  → SyncService sends when online
  → On success: mark synced
  → On failure: retry later
```

### Offline scenario
```
User opens app (no network)
  → Reads from SwiftData → sees all their data
User checks in a task
  → SwiftData updated → UI shows check mark
  → API call fails → queued in SyncQueue
Network comes back
  → SyncService drains queue → all pending writes sent
```

## Layers

```
┌─────────────────────────────┐
│         Views (SwiftUI)     │  Reads: @Query or ViewModel @Published
│         ViewModels          │  Writes: calls Repository methods
├─────────────────────────────┤
│        Repository           │  Single interface for data access
│  ┌──────────┬──────────┐    │  Reads from local DB
│  │ SwiftData│ SyncSvc  │    │  Writes to local DB + queues sync
│  └──────────┴──────────┘    │
├─────────────────────────────┤
│       ApiService            │  HTTP client (unchanged)
├─────────────────────────────┤
│       Server API            │  Remote backend
└─────────────────────────────┘
```

## SwiftData Models

Mirror the API types but stored locally:

```swift
@Model class CachedTask {
    @Attribute(.unique) var id: String
    var title: String
    var type: String              // "Recurring" or "OneTime"
    var currentStreak: Int
    var longestStreak: Int
    var daysRemaining: Int?
    var progress: Int
    var checkedIn: Bool
    var completedToday: Bool?
    var lastSyncedAt: Date?
}

@Model class CachedConversation {
    @Attribute(.unique) var id: String
    var title: String
    var lastMessage: String
    var updatedAt: Date
}

@Model class SyncQueueItem {
    var id: String                // UUID
    var method: String            // POST, PATCH, DELETE
    var path: String              // /goals/{id}/checkin
    var body: Data?               // JSON payload
    var createdAt: Date
    var retryCount: Int
}
```

## Repository Pattern

```swift
class TaskRepository {
    let modelContext: ModelContext
    let api: ApiService
    let sync: SyncService

    // READS — always from local DB
    func getRecurringTasks() -> [CachedTask]
    func getMilestones() -> [CachedTask]

    // WRITES — local first, then queue sync
    func checkIn(id: String, completed: Bool, date: String)
    func undoCheckIn(id: String, date: String)
    func createTask(title: String, type: String, targetDate: String?)
    func deleteTask(id: String)
    func updateProgress(id: String, value: Int)

    // SYNC — pull fresh data from server
    func refreshFromServer() async
}
```

## SyncService

Manages the queue of pending writes:

```swift
class SyncService {
    func enqueue(method: String, path: String, body: Encodable?)
    func drain() async          // Send all pending items
    func startMonitoring()      // Watch for connectivity changes
}
```

**Retry strategy:**
- Immediate retry on transient errors (timeout, no connection)
- Max 5 retries per item
- Exponential backoff: 1s, 2s, 4s, 8s, 16s (tracked via `lastAttemptedAt` on each queue item)
- Items older than 24h are discarded
- 401 errors don't count as retries (token refresh handled automatically)
- Drain is guarded by `isDraining` flag to prevent concurrent processing

**Conflict resolution:**
- Server wins for reads — but only for tasks without `hasPendingChanges`
- Client wins for pending writes (queued actions always sent)
- If a write fails with 404 (resource deleted server-side), discard the queue item immediately
- Tasks with `hasPendingChanges == true` are protected from server overwrites and deletion during refresh
- After successful sync, `hasPendingChanges` is cleared and `lastSyncedAt` updated

**Create task flow:**
- Task created locally with temp UUID, `hasPendingChanges = true`
- Queued as POST with `tempId` set on the `SyncQueueItem`
- On sync success, `SyncService` decodes server response to get real ID
- Temp ID replaced in local DB and remaining queue items that reference it
- `TaskRepository.replaceTempWithReal()` handles the swap

**Sync status (UI indicators):**
- `SyncStatus.shared.syncing` — true while drain is in progress
- `SyncStatus.shared.pendingCount` — number of unsynced queue items
- `task.hasPendingChanges` — per-task flag for showing pending dot

**DB migration safety:**
- If SwiftData migration fails on app launch (schema change), the local store is deleted and recreated
- Data is re-fetched from server on next refresh — no data loss since server is authoritative for reads

## Network Reachability

Use `NWPathMonitor` to detect connectivity:

```swift
class NetworkMonitor: ObservableObject {
    @Published var isConnected = true

    init() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue.global())
    }
}
```

When `isConnected` becomes `true`, trigger `SyncService.drain()`.

## Migration from Current Architecture

### Before (current)
```
HomeView → HomeViewModel → ApiService → Server
```

### After (offline-first)
```
HomeView → HomeViewModel → TaskRepository → SwiftData (reads)
                                          → SyncService → ApiService (writes)
```

### Steps
1. Add SwiftData models (`CachedTask`, `CachedConversation`, `SyncQueueItem`)
2. Create `TaskRepository` with read/write methods
3. Create `SyncService` with queue and retry
4. Create `NetworkMonitor`
5. Update `HomeViewModel` to use `TaskRepository` instead of `ApiService`
6. Update `JourneyView` and `ReflectView` similarly
7. Remove the file-based `CacheService` (replaced by SwiftData)

## What Works Offline

| Feature | Offline Support |
|---------|----------------|
| View tasks | Full — reads from local DB |
| Check in / skip | Full — writes locally, syncs later |
| Create task | Full — creates locally, syncs later |
| Delete task | Full — deletes locally, syncs later |
| Update progress | Full — updates locally, syncs later |
| View conversations | Full — cached locally |
| AI Chat | No — requires server (streaming) |
| View journey/streaks | Full — computed from local data |
| View goal detail | Full — cached locally |

## UI Indicators

- Show a subtle "offline" badge when `NetworkMonitor.isConnected == false`
- Show "syncing..." when `SyncService` is draining the queue
- Show a dot on tasks that have pending (unsynced) changes
