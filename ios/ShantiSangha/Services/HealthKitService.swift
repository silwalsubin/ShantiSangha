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

    /// Steps recorded so far today across all sources. `nil` means "not read
    /// yet" (or user denied); UI should hide the field rather than show zero.
    @Published private(set) var stepsToday: Int?

    /// Hours asleep last night (6pm previous day → 11am today), summed across
    /// all asleep categories. `nil` means "not read yet" or no data.
    @Published private(set) var sleepHoursLastNight: Double?

    /// Total mindful minutes logged today across ALL sources — ours plus
    /// Calm, Headspace, Apple's own Mindful app, anything. This is the real
    /// "did you sit today" number, and will power auto-streak-credit in
    /// Phase 3.
    @Published private(set) var mindfulMinutesTotalToday: Int?

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

    // MARK: - Reads

    /// Reads everything we surface on Home. Safe to call even when some
    /// permissions were denied — each read fails gracefully and leaves its
    /// published property nil.
    func refreshWholeDayContext() async {
        guard isEnabled, isAvailable else { return }
        async let steps = queryStepsToday()
        async let sleep = querySleepLastNight()
        async let mindful = queryMindfulMinutesToday(allSources: true)
        let (s, sl, m) = await (steps, sleep, mindful)
        stepsToday = s
        sleepHoursLastNight = sl
        mindfulMinutesTotalToday = m
    }

    private func queryStepsToday() async -> Int? {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return nil }

        let start = Calendar.current.startOfDay(for: Date())
        let end = Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return await withCheckedContinuation { (cont: CheckedContinuation<Int?, Never>) in
            let q = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let steps = result?.sumQuantity()?.doubleValue(for: .count())
                cont.resume(returning: steps.map { Int($0) })
            }
            store.execute(q)
        }
    }

    /// Sleep "last night" = 6pm previous day → 11am today, summing any
    /// asleep category (core, deep, REM, or legacy "asleep").
    private func querySleepLastNight() async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }

        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        guard let windowStart = cal.date(byAdding: .hour, value: -6, to: todayStart),
              let windowEnd = cal.date(byAdding: .hour, value: 11, to: todayStart) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: [])

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

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ]

        let seconds = samples
            .filter { asleepValues.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

        guard seconds > 0 else { return nil }
        return seconds / 3600.0
    }

    /// Total mindful minutes today, optionally including samples from other
    /// apps (Calm, Headspace, Apple Mindful). When `allSources` is false,
    /// only this app's contributions count.
    private func queryMindfulMinutesToday(allSources: Bool) async -> Int? {
        guard let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return nil }

        let start = Calendar.current.startOfDay(for: Date())
        let end = Date()
        let datePred = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let predicate: NSPredicate
        if allSources {
            predicate = datePred
        } else {
            let sourcePred = HKQuery.predicateForObjects(from: HKSource.default())
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePred, sourcePred])
        }

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

        let seconds = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        guard seconds > 0 else { return nil }
        return Int(seconds / 60.0)
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
