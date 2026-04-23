import Foundation
import HealthKit

/// Phase 1: write-only integration with Apple Health.
/// When the user completes a meditation-type recurring goal, we log a
/// mindful session covering the last `defaultSessionMinutes` minutes, so
/// ShantiSangha contributes to the user's Health / Fitness app alongside
/// whatever else they practice.
///
/// Reads (sleep, HRV, mindfulness from other apps) land in Phase 2, when
/// the backend gains a wellness-context endpoint.
@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    /// User-visible opt-in. When off, nothing is requested and nothing is written.
    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "healthKitEnabled") {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "healthKitEnabled") }
    }

    /// Default duration attributed to a check-in when we don't know how long
    /// the user actually sat. Tunable later via per-goal settings.
    let defaultSessionMinutes: Int = 10

    /// Total mindful minutes written by this app today — surfaced in Settings
    /// as a confidence-building diagnostic.
    @Published private(set) var minutesWrittenToday: Int = 0

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    /// Requests the write permissions we need in Phase 1, plus the read
    /// permissions Phase 2 will use — asking once up-front is gentler than
    /// a second permission sheet later. HealthKit does not let apps observe
    /// read authorization status, so we always call this on enable and rely
    /// on the query layer to fail gracefully when a type was denied.
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }

        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!
        ]

        var typesToRead: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!
        ]
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            typesToRead.insert(hrv)
        }

        do {
            try await store.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            AppLogger.shared.info("Health", "Authorization request completed")
            await refreshTodayMinutes()
            return true
        } catch {
            AppLogger.shared.error("Health", "Authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Write

    /// Records a mindful session ending now, covering the last `minutes`.
    /// No-op when the user hasn't enabled Health sync.
    func logMindfulSession(minutes: Int? = nil, endedAt end: Date = Date()) async {
        guard isEnabled, isAvailable else { return }
        guard let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return }

        let duration = minutes ?? defaultSessionMinutes
        let start = end.addingTimeInterval(TimeInterval(-duration * 60))

        let sample = HKCategorySample(
            type: type,
            value: HKCategoryValue.notApplicable.rawValue,
            start: start,
            end: end,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )

        do {
            try await store.save(sample)
            AppLogger.shared.info("Health", "Logged mindful session: \(duration) min")
            await refreshTodayMinutes()
        } catch {
            AppLogger.shared.error("Health", "Failed to log mindful session: \(error.localizedDescription)")
        }
    }

    // MARK: - Diagnostic: today's minutes written by us

    /// Sum of mindful-session durations originating from this app today.
    /// Shown in Settings so the user can see the integration working.
    func refreshTodayMinutes() async {
        guard isAvailable,
              let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            return
        }

        let start = Calendar.current.startOfDay(for: Date())
        let end = Date()
        let datePred = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sourcePred = HKQuery.predicateForObjects(from: HKSource.default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePred, sourcePred])

        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, _ in
                cont.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }

        let totalSeconds = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        minutesWrittenToday = Int(totalSeconds / 60.0)
    }

    // MARK: - Classification

    /// Heuristic: does this recurring goal title count as a "mindful" practice
    /// that should be mirrored to Apple Health? Phase 2 will replace this with
    /// an explicit per-goal setting.
    static func countsAsMindful(title: String) -> Bool {
        let lower = title.lowercased()
        let keywords = ["meditat", "mindful", "breath", "pranayam", " sit ", "sitting", "dhyan", "japa", "mantra"]
        if keywords.contains(where: { lower.contains($0) }) { return true }
        // Starts-with match for short titles like "Sit" or "Breathe"
        let firstWord = lower.split(separator: " ").first.map(String.init) ?? lower
        return ["sit", "breathe", "meditate"].contains(firstWord)
    }
}
