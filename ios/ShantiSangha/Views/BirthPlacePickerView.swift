import SwiftUI
import MapKit
import CoreLocation

/// Search-first picker for birth place. The search bar is primary; the map
/// is a confirmation preview after a result is chosen. Uses MKLocalSearch
/// with a worldwide region and both address + POI result types so smaller
/// towns and internationally-named places resolve.
struct BirthPlacePickerView: View {
    let selectedPlace: String
    let onSelect: (_ name: String, _ lat: Double, _ lng: Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?

    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedName = ""
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                // Either the live results or the selection preview
                if selectedCoordinate != nil {
                    selectionPreview
                } else {
                    resultsList
                }
            }
            .background(Color.sacredBg.ignoresSafeArea())
            .navigationTitle("Place of birth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.sacredMuted)
                }
            }
            .onAppear {
                if !selectedPlace.isEmpty {
                    searchText = selectedPlace
                    scheduleSearch()
                }
            }
        }
        // When the user has picked a result but not yet committed with
        // "Use this place", block the drag-dismiss gesture so they don't
        // lose the selection by accident. Cancel still works via the toolbar.
        .interactiveDismissDisabled(selectedCoordinate != nil)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)

            TextField("Search city, town, or village", text: $searchText)
                .font(.sacredText)
                .foregroundColor(.sacredText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .onChange(of: searchText) { _, newValue in
                    // Typing clears any previous selection so the user can pick again
                    if selectedCoordinate != nil {
                        selectedCoordinate = nil
                        selectedName = ""
                    }
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
                    selectedCoordinate = nil
                    selectedName = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sacredGold.opacity(0.1)))
    }

    // MARK: - Results list

    private var resultsList: some View {
        ScrollView {
            if searchText.isEmpty {
                VStack(spacing: 8) {
                    Text("Start typing your birth city.")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else if searchResults.isEmpty && !searching {
                VStack(spacing: 8) {
                    Text("No matches.")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                    Text("Try the English name or include the country.")
                        .font(.sacredMicro)
                        .foregroundColor(.sacredMuted.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(searchResults.enumerated()), id: \.offset) { index, item in
                        Button { selectItem(item) } label: {
                            resultRow(item)
                        }
                        .buttonStyle(.plain)

                        if index < searchResults.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func resultRow(_ item: MKMapItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.sacredIcon)
                .foregroundColor(.sacredGold)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryName(for: item))
                    .font(.sacredTextMedium)
                    .foregroundColor(.sacredText)
                let subtitle = subtitleLine(for: item)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    // MARK: - Selection preview

    private var selectionPreview: some View {
        VStack(spacing: 16) {
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                if let coord = selectedCoordinate {
                    Marker(selectedName, coordinate: coord)
                        .tint(Color.sacredGold)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sacredGold.opacity(0.1)))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            VStack(spacing: 4) {
                Text(selectedName)
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredText)
                if let coord = selectedCoordinate {
                    Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                        .font(.sacredMicro)
                        .foregroundColor(.sacredMuted)
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            SacredPrimaryButton("Use this place", fullWidth: true) {
                if let coord = selectedCoordinate {
                    onSelect(selectedName, coord.latitude, coord.longitude)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Search

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
            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms debounce
            if Task.isCancelled { return }
            await performSearch(query: query)
        }
    }

    private func performSearch(query: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        // Search worldwide — without this, results bias toward the device's
        // current region and miss international cities.
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

    // MARK: - Selection

    private func selectItem(_ item: MKMapItem) {
        let coord = item.placemark.coordinate
        let name = displayName(for: item)

        selectedCoordinate = coord
        selectedName = name
        searchText = name
        searchResults = []
        searching = false

        position = .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        ))
    }

    // MARK: - Display helpers

    private func primaryName(for item: MKMapItem) -> String {
        if let locality = item.placemark.locality, !locality.isEmpty {
            return locality
        }
        if let subLocality = item.placemark.subLocality, !subLocality.isEmpty {
            return subLocality
        }
        if let admin = item.placemark.administrativeArea, !admin.isEmpty {
            return admin
        }
        return item.name ?? "Unknown"
    }

    private func subtitleLine(for item: MKMapItem) -> String {
        var parts: [String] = []
        let primary = primaryName(for: item)
        if let admin = item.placemark.administrativeArea,
           !admin.isEmpty,
           admin != primary {
            parts.append(admin)
        }
        if let country = item.placemark.country, !country.isEmpty {
            parts.append(country)
        }
        return parts.joined(separator: ", ")
    }

    private func displayName(for item: MKMapItem) -> String {
        let primary = primaryName(for: item)
        let subtitle = subtitleLine(for: item)
        return subtitle.isEmpty ? primary : "\(primary), \(subtitle)"
    }
}
