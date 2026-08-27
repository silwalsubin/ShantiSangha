import SwiftUI
import MapKit
import CoreLocation

/// Form body for the location gate. Search is the primary path; "Use my
/// current location" is offered below for users who prefer one-tap. After a
/// pick, we show what we extracted (country / state / city) so the user
/// can confirm before continuing — never silently submit a misread.
struct LocationGateBody: View {
    @EnvironmentObject private var profile: ProfileService

    let submitLabel: String
    let onSaved: (() -> Void)?

    @State private var searchText: String = ""
    @State private var searching: Bool = false
    @State private var searchResults: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?

    @State private var selection: ResolvedLocation?
    @State private var resolving: Bool = false
    @State private var saving: Bool = false
    @State private var errorMessage: String?

    @StateObject private var locationFetcher = OneShotLocationFetcher()

    init(submitLabel: String = "Continue", onSaved: (() -> Void)? = nil) {
        self.submitLabel = submitLabel
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: SacredSpacing.m) {
            searchField

            if selection == nil {
                useCurrentLocationLink
            }

            if let selection {
                selectionCard(selection)
            } else if !searchText.isEmpty {
                resultsList
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SacredPrimaryButton(
                submitLabel,
                style: .commit,
                isDisabled: selection == nil,
                isLoading: saving
            ) {
                Task { await submit() }
            }
        }
        .onAppear {
            // Pre-fill from cached profile if returning to this gate.
            if selection == nil,
               let p = profile.profile,
               let country = p.country?.nonEmpty,
               let state = p.state?.nonEmpty,
               let city = p.city?.nonEmpty {
                selection = ResolvedLocation(country: country, state: state, city: city)
                searchText = "\(city), \(state), \(country)"
            }
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: SacredSpacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)

            TextField("Search city, town, or village", text: $searchText)
                .typingHaptics(for: searchText)
                .font(.sacredText)
                .foregroundColor(.sacredText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onChange(of: searchText) { _, _ in
                    // Typing clears any prior selection so the user can pick again.
                    if selection != nil { selection = nil }
                    scheduleSearch()
                }

            if searching {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.sacredGold)
            } else if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                    selection = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SacredSpacing.m)
        .padding(.vertical, 14)
        .luxCardChrome()
    }

    // MARK: - Use current location

    private var useCurrentLocationLink: some View {
        Button {
            Task { await useCurrentLocation() }
        } label: {
            HStack(spacing: 6) {
                if resolving {
                    ProgressView().scaleEffect(0.7).tint(.sacredGold)
                } else {
                    Image(systemName: "location.fill")
                        .font(.sacredSmall)
                }
                Text(resolving ? "Reading your location…" : "Use my current location")
                    .font(.sacredSmallSemibold)
            }
            .foregroundColor(.sacredGold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(resolving)
    }

    // MARK: - Results list

    private var resultsList: some View {
        VStack(spacing: 0) {
            if searchResults.isEmpty && !searching {
                Text("No matches. Try the English name or include the country.")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, SacredSpacing.s)
            } else {
                ForEach(Array(searchResults.enumerated()), id: \.offset) { index, item in
                    Button { selectMapItem(item) } label: {
                        resultRow(item)
                    }
                    .buttonStyle(.plain)

                    if index < searchResults.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
        .luxCardChrome()
    }

    private func resultRow(_ item: MKMapItem) -> some View {
        HStack(spacing: SacredSpacing.s) {
            Image(systemName: "mappin.circle.fill")
                .font(.sacredIcon)
                .foregroundColor(.sacredGold)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLabel(for: item))
                    .font(.sacredTextMedium)
                    .foregroundColor(.sacredText)
                let sub = subtitleLabel(for: item)
                if !sub.isEmpty {
                    Text(sub)
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, SacredSpacing.m)
        .contentShape(Rectangle())
    }

    // MARK: - Selection card

    private func selectionCard(_ loc: ResolvedLocation) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredGold)
                Text("WE FOUND")
                    .font(.sacredSectionLabel)
                    .tracking(3)
                    .foregroundColor(.sacredLabel)
            }

            Text(loc.city)
                .font(.sacredSubheading)
                .foregroundColor(.sacredText)

            Text("\(loc.state), \(loc.country)")
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)
        }
        .padding(SacredSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxCardChrome()
    }

    // MARK: - Search wiring

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            searching = false
            return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            await performSearch(query: query)
        }
    }

    private func performSearch(query: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        // Worldwide so international names resolve.
        request.region = MKCoordinateRegion(MKMapRect.world)
        do {
            let response = try await MKLocalSearch(request: request).start()
            if Task.isCancelled { return }
            searchResults = response.mapItems
        } catch {
            if Task.isCancelled { return }
            searchResults = []
        }
        searching = false
    }

    private func selectMapItem(_ item: MKMapItem) {
        // iOS 26 — `MKMapItem.placemark` is deprecated. Use the new
        // `MKReverseGeocodingRequest` to resolve the location and parse
        // `MKAddress.fullAddress` into structured fields. Note: this
        // turns selection into an async network round-trip (was sync).
        Task { @MainActor in
            searching = true
            defer { searching = false }
            do {
                let request = MKReverseGeocodingRequest(location: item.location)
                let mapItems = try await request?.mapItems ?? []
                let resolvedFromRequest = mapItems.first.flatMap { ResolvedLocation(mapItem: $0) }
                let resolved = resolvedFromRequest ?? ResolvedLocation(mapItem: item)
                guard let resolved else {
                    errorMessage = "We couldn't read that place. Try another nearby city."
                    return
                }
                selection = resolved
                searchText = "\(resolved.city), \(resolved.state), \(resolved.country)"
                searchResults = []
                errorMessage = nil
            } catch {
                errorMessage = "We couldn't read that place. Try another nearby city."
            }
        }
    }

    // MARK: - Current location

    private func useCurrentLocation() async {
        resolving = true
        errorMessage = nil
        defer { resolving = false }
        do {
            let location = try await locationFetcher.fetch()
            // iOS 26 — `CLGeocoder` is deprecated; use MapKit's
            // `MKReverseGeocodingRequest` to resolve a coordinate to
            // a place. The returned `MKMapItem.address.fullAddress` is
            // a locale-formatted string we parse into city/state/country.
            let request = MKReverseGeocodingRequest(location: location)
            let mapItems = try await request?.mapItems ?? []
            guard let mapItem = mapItems.first,
                  let resolved = ResolvedLocation(mapItem: mapItem)
            else {
                errorMessage = "We couldn't read your location. Try searching instead."
                return
            }
            selection = resolved
            searchText = "\(resolved.city), \(resolved.state), \(resolved.country)"
            searchResults = []
        } catch let clError as CLError where clError.code == .denied {
            errorMessage = "Location permission denied. Search for your city instead."
        } catch {
            errorMessage = "We couldn't read your location. Try searching instead."
        }
    }

    // MARK: - Submit

    private func submit() async {
        guard let selection, !saving else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            try await profile.update(UpdateMeRequest(
                country: selection.country,
                state: selection.state,
                city: selection.city
            ))
            onSaved?()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "We couldn't save that. Try again."
        }
    }

    // MARK: - Display helpers

    private func primaryLabel(for item: MKMapItem) -> String {
        // iOS 26 — `MKMapItem.placemark` is deprecated. We use
        // `item.name` (usually the place's display name) and fall
        // back to `MKAddress.shortAddress`. Coarser than the old
        // locality/subLocality cascade but doesn't trigger warnings.
        item.name ?? item.address?.shortAddress ?? "Unknown"
    }

    private func subtitleLabel(for item: MKMapItem) -> String {
        item.address?.shortAddress ?? ""
    }
}

// MARK: - Resolved location

/// Three required fields extracted from a `CLPlacemark`. Returns nil if
/// any of country / state / city is missing — the gate's predicate
/// requires all three.
private struct ResolvedLocation: Equatable {
    let country: String
    let state: String
    let city: String

    init(country: String, state: String, city: String) {
        self.country = country
        self.state = state
        self.city = city
    }

    /// iOS 26 — parses a structured location from `MKMapItem.address.fullAddress`.
    /// `fullAddress` is a locale-formatted string (e.g. "1 Apple Park Way,
    /// Cupertino, CA 95014, United States"). We split on commas and read
    /// city / state / country positionally:
    ///   - last segment is country
    ///   - second-to-last is state/region (if 3+ segments)
    ///   - the segment before that is the city (if 4+ segments) or the
    ///     first segment (if exactly 3 segments)
    /// US-style postal codes ("CA 95014") are stripped from the state slot.
    /// Lossier than the old CLPlacemark path, but the iOS 26 MapKit
    /// migration doesn't expose granular structured fields.
    init?(mapItem: MKMapItem) {
        guard let fullAddress = mapItem.address?.fullAddress, !fullAddress.isEmpty else {
            return nil
        }

        let parts = fullAddress
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard parts.count >= 2, let country = parts.last, !country.isEmpty else {
            return nil
        }

        let stateSlot: String
        let citySlot: String
        if parts.count >= 4 {
            stateSlot = parts[parts.count - 2]
            citySlot = parts[parts.count - 3]
        } else if parts.count == 3 {
            stateSlot = parts[1]
            citySlot = parts[0]
        } else {
            stateSlot = country
            citySlot = parts[0]
        }

        let strippedState = ResolvedLocation.stripPostalCode(stateSlot)
        let state = strippedState.isEmpty ? country : strippedState
        let city = citySlot

        guard !city.isEmpty else { return nil }
        self.country = country
        self.state = state
        self.city = city
    }

    /// Trim trailing digits / spaces / hyphens that look like a postal
    /// code, leaving the admin region name (e.g. "CA 95014" → "CA").
    private static func stripPostalCode(_ s: String) -> String {
        var chars = Array(s)
        while let last = chars.last, last.isNumber || last == " " || last == "-" {
            chars.removeLast()
        }
        return String(chars).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - One-shot location fetcher

/// Async/await wrapper around `CLLocationManager` for a single location
/// reading. Requests `whenInUse` authorization on first call. Throws
/// `CLError(.denied)` when the user declines.
@MainActor
private final class OneShotLocationFetcher: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func fetch() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
                // requestLocation fires after authorization callback below.
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                resume(.failure(CLError(.denied)))
            @unknown default:
                resume(.failure(CLError(.denied)))
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                self.resume(.failure(CLError(.denied)))
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let last = locations.last {
                self.resume(.success(last))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.resume(.failure(error))
        }
    }

    private func resume(_ result: Result<CLLocation, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        switch result {
        case .success(let loc): cont.resume(returning: loc)
        case .failure(let err): cont.resume(throwing: err)
        }
    }
}

// MARK: - String helper

private extension String {
    /// Returns self if non-empty after trimming, else nil.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
