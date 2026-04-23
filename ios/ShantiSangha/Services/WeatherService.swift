import Foundation
import CoreLocation
import WeatherKit

/// Phase 1: fetches today's weather on demand, caches for the rest of the
/// day, and surfaces a lightweight snapshot for UI confirmation. Phase 2
/// will feed this into the backend reflection prompt (as an invisible
/// context layer, per the product guardian's invisible-content rule).
@MainActor
final class WeatherService: NSObject, ObservableObject {
    static let shared = WeatherService()

    /// User-visible opt-in. When off, we never request location or network.
    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "weatherKitEnabled") {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "weatherKitEnabled") }
    }

    /// Last successful snapshot, if any — used by Settings to confirm the
    /// integration is live, and by Phase 2 to ship into the reflection.
    @Published private(set) var snapshot: Snapshot?

    /// Surface-level permission state so the UI can explain what's happening
    /// when the user taps the toggle but the system sheet doesn't appear
    /// (because they previously denied it).
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    struct Snapshot: Equatable {
        let temperatureF: Double
        let conditionSymbol: String      // SF Symbol name
        let conditionLabel: String       // "Partly cloudy"
        let sunrise: Date?
        let sunset: Date?
        let fetchedAt: Date

        var temperatureLabel: String {
            "\(Int(temperatureF.rounded()))°F"
        }
    }

    private let locationManager = CLLocationManager()
    private let weather = WeatherService.sharedInstance
    private var pendingLocationContinuation: CheckedContinuation<CLLocation?, Never>?

    // WeatherKit's own singleton is `WeatherService` — same name as us. We
    // shadow it with a private alias to avoid a compiler ambiguity here.
    private static let sharedInstance = WeatherKit.WeatherService.shared

    override init() {
        super.init()
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Enable flow

    /// Called when the user flips the toggle on. Requests when-in-use
    /// location permission and, if granted, fetches a snapshot. Returns
    /// whether we ended up enabled + fetched successfully.
    @discardableResult
    func requestPermissionAndFetch() async -> Bool {
        authorizationStatus = locationManager.authorizationStatus

        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            // Wait for delegate to deliver the new status before continuing.
            try? await Task.sleep(nanoseconds: 500_000_000)
            authorizationStatus = locationManager.authorizationStatus
        case .restricted, .denied:
            AppLogger.shared.info("Weather", "Location permission denied — cannot fetch")
            return false
        default:
            break
        }

        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return false
        }

        return await refreshIfStale()
    }

    /// Returns true if we have a snapshot younger than `maxAge`; otherwise
    /// fetches fresh. Called from Phase 2 callers that want weather without
    /// hammering the API.
    @discardableResult
    func refreshIfStale(maxAge: TimeInterval = 3600) async -> Bool {
        if let snap = snapshot, Date().timeIntervalSince(snap.fetchedAt) < maxAge {
            return true
        }
        return await fetch()
    }

    // MARK: - Fetch

    private func fetch() async -> Bool {
        guard isEnabled else { return false }
        guard let location = await currentLocation() else {
            AppLogger.shared.error("Weather", "Failed to get location")
            return false
        }

        do {
            let current = try await weather.weather(for: location, including: .current)
            let daily = try? await weather.weather(for: location, including: .daily)
            let today = daily?.first
            let fahrenheit = current.temperature.converted(to: .fahrenheit).value
            snapshot = Snapshot(
                temperatureF: fahrenheit,
                conditionSymbol: current.symbolName,
                conditionLabel: current.condition.description,
                sunrise: today?.sun.sunrise,
                sunset: today?.sun.sunset,
                fetchedAt: Date()
            )
            AppLogger.shared.info("Weather", "Fetched: \(snapshot!.temperatureLabel), \(snapshot!.conditionLabel)")
            return true
        } catch {
            AppLogger.shared.error("Weather", "Fetch failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Location

    private func currentLocation() async -> CLLocation? {
        if let recent = locationManager.location,
           Date().timeIntervalSince(recent.timestamp) < 600 {
            return recent
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            pendingLocationContinuation = cont
            locationManager.requestLocation()
        }
    }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.pendingLocationContinuation?.resume(returning: locations.first)
            self.pendingLocationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            AppLogger.shared.error("Weather", "Location error: \(error.localizedDescription)")
            self.pendingLocationContinuation?.resume(returning: nil)
            self.pendingLocationContinuation = nil
        }
    }
}
