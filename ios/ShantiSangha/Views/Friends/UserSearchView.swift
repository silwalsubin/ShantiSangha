import SwiftUI

/// Find-people screen pushed from the Friends tab. Two text inputs (name +
/// optional location), a debounced search that fires 300 ms after the last
/// keystroke, and an infinite-scroll list of results. Tapping a result
/// presents a read-only profile preview sheet — the deferred connect
/// action lives there.
struct UserSearchView: View {
    @StateObject private var vm = UserSearchViewModel()
    @State private var selectedResult: UserSearchResult?
    @FocusState private var nameFocused: Bool
    private let initialQuery: String?

    init(initialQuery: String? = nil) {
        self.initialQuery = initialQuery
    }

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: SacredSpacing.s) {
                    searchInputs
                        .padding(.horizontal, SacredSpacing.m)
                        .padding(.top, SacredSpacing.m)

                    if let err = vm.errorMessage {
                        Text(err)
                            .font(.sacredSmall)
                            .foregroundColor(.sacredRed)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, SacredSpacing.m)
                    }

                    if !vm.hasFilters {
                        SacredEmptyState(
                            icon: "magnifyingglass",
                            title: "Type a name",
                            subtitle: "We'll show you who matches.")
                    } else if vm.loading && vm.results.isEmpty {
                        ProgressView()
                            .padding(.top, SacredSpacing.xl)
                    } else if vm.results.isEmpty {
                        SacredEmptyState(
                            icon: "person.crop.circle.badge.questionmark",
                            title: "No one matches",
                            subtitle: "Try a different spelling or remove the location filter.")
                    } else {
                        resultsList

                        if vm.loadingMore {
                            ProgressView()
                                .padding(.vertical, SacredSpacing.m)
                        }
                    }

                    Color.clear.frame(height: SacredSpacing.tabBarSafe)
                }
            }
        }
        .navigationTitle("Find people")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: vm.query) { _, _ in vm.scheduleSearch() }
        .onChange(of: vm.location) { _, _ in vm.scheduleSearch() }
        .onAppear {
            // Seed once when navigated in from the circle search bar so
            // the user lands on the same query they were typing — the
            // .onChange(of: vm.query) above kicks the debounced fetch.
            if let initial = initialQuery, vm.query.isEmpty {
                vm.query = initial
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                nameFocused = true
            }
        }
        .onDisappear { vm.reset() }
        .sheet(item: $selectedResult) { result in
            UserProfilePreviewSheet(result: result)
        }
    }

    // MARK: - Inputs

    @ViewBuilder
    private var searchInputs: some View {
        VStack(spacing: SacredSpacing.s) {
            searchField(
                placeholder: "Find by name",
                text: $vm.query,
                icon: "magnifyingglass",
                showSpinner: vm.loading && vm.results.isEmpty,
                focused: $nameFocused,
                autoCapitalize: .words)

            searchField(
                placeholder: "City, state, or country (optional)",
                text: $vm.location,
                icon: "mappin.and.ellipse",
                showSpinner: false,
                focused: nil,
                autoCapitalize: .words)
        }
    }

    /// Reusable styling matching the search bar in BirthPlacePickerView —
    /// rounded rect, ultra-thin material, gold-stroke overlay, magnifying
    /// glass leading icon, optional clear-X button trailing, optional
    /// spinner during in-flight requests.
    @ViewBuilder
    private func searchField(
        placeholder: String,
        text: Binding<String>,
        icon: String,
        showSpinner: Bool,
        focused: FocusState<Bool>.Binding?,
        autoCapitalize: TextInputAutocapitalization
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)

            Group {
                if let focused = focused {
                    TextField(placeholder, text: text)
                        .focused(focused)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.sacredText)
            .foregroundColor(.sacredText)
            .autocorrectionDisabled()
            .textInputAutocapitalization(autoCapitalize)

            if showSpinner {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.sacredGold)
            } else if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sacredGold.opacity(0.1)))
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        VStack(spacing: SacredSpacing.s) {
            ForEach(Array(vm.results.enumerated()), id: \.element.id) { index, result in
                Button {
                    selectedResult = result
                } label: {
                    ResultRow(result: result)
                }
                .buttonStyle(.plain)
                .onAppear {
                    // Infinite-scroll trigger: when one of the last 5 rows
                    // becomes visible, fire the next page. The VM's own
                    // guards prevent over-firing.
                    if index >= vm.results.count - 5 {
                        vm.loadNext()
                    }
                }
            }
        }
        .padding(.horizontal, SacredSpacing.m)
    }
}

private struct ResultRow: View {
    let result: UserSearchResult

    var body: some View {
        HStack(spacing: SacredSpacing.s) {
            SacredAvatar(
                displayName: result.displayName,
                avatarUrl: result.avatarUrl,
                size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.displayName)
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredText)
                if let loc = result.locationString {
                    Text(loc)
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.sacredMuted.opacity(0.5))
        }
        .padding(SacredSpacing.s)
        .luxCardChrome()
    }
}
