import SwiftUI
import MapKit

/// Map-based location picker for selecting birth place.
/// Search for a city, tap on the map, or use a search result.
struct BirthPlacePickerView: View {
    let selectedPlace: String
    let onSelect: (_ name: String, _ lat: Double, _ lng: Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedName = ""
    @State private var marker: PlaceMark?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Map
                Map(position: $position) {
                    if let marker {
                        Marker(marker.name, coordinate: marker.coordinate)
                            .tint(Color.sacredGold)
                    }
                }
                .mapStyle(.standard)
                .onTapGesture { location in
                    // MapReader would be needed for coordinate from tap,
                    // but search-based selection is more reliable for birth place
                }

                // Search overlay
                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                        TextField("Search city or place", text: $searchText)
                            .font(.sacredText)
                            .onSubmit { search() }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Search results
                    if !searchResults.isEmpty {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(searchResults, id: \.self) { item in
                                    Button {
                                        selectItem(item)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "mappin.circle.fill")
                                                .font(.sacredIcon)
                                                .foregroundColor(.sacredGold)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.name ?? "Unknown")
                                                    .font(.sacredTextMedium)
                                                    .foregroundColor(.sacredText)
                                                if let locality = item.placemark.locality,
                                                   let country = item.placemark.country {
                                                    Text("\(locality), \(country)")
                                                        .font(.sacredSmall)
                                                        .foregroundColor(.sacredMuted)
                                                }
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 16)
                                    }
                                    .buttonStyle(.plain)
                                    Divider().padding(.leading, 44)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }

                    Spacer()

                    // Confirm button
                    if selectedCoordinate != nil {
                        Button {
                            onSelect(selectedName, selectedCoordinate!.latitude, selectedCoordinate!.longitude)
                        } label: {
                            Text("Select \(selectedName)")
                                .font(.sacredTextSemibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(LinearGradient.sacredGoldShiny)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            .navigationTitle("Place of birth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.sacredMuted)
                }
            }
            .onAppear { searchText = selectedPlace }
        }
    }

    private func search() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.resultTypes = .address

        Task {
            do {
                let response = try await MKLocalSearch(request: request).start()
                searchResults = response.mapItems
            } catch {
                searchResults = []
            }
        }
    }

    private func selectItem(_ item: MKMapItem) {
        let coord = item.placemark.coordinate
        selectedCoordinate = coord
        searchResults = []

        // Build display name
        let parts = [item.placemark.locality, item.placemark.country].compactMap { $0 }
        selectedName = parts.isEmpty ? (item.name ?? "Selected location") : parts.joined(separator: ", ")
        searchText = selectedName

        marker = PlaceMark(name: selectedName, coordinate: coord)
        position = .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
        ))
    }
}

private struct PlaceMark: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
}
