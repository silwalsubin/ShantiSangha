import Foundation
import Combine
import FirebaseAuth

// MARK: - DTOs

/// Mirror of the backend `ProfileResponse` returned by `GET /api/me`.
/// Keep field names in sync with `backend/ShantiSangha.Identity/Contracts/UserContracts.cs`.
struct ProfileResponse: Codable, Equatable {
    let displayName: String?
    let timezone: String?
    let reminderHour: Int?
    let onboardingCompleted: Bool
    let birthDate: String?
    let birthTime: String?
    let birthPlace: String?
    let country: String?
    let state: String?
    let city: String?

    /// Defensive default used by the gate orchestrator when `/me` somehow
    /// returns a null profile — every gate predicate fails against this so
    /// the user is prompted instead of slipping through to the main app.
    static let empty = ProfileResponse(
        displayName: nil,
        timezone: nil,
        reminderHour: nil,
        onboardingCompleted: false,
        birthDate: nil,
        birthTime: nil,
        birthPlace: nil,
        country: nil,
        state: nil,
        city: nil
    )
}

/// Wrapper around the backend `UserResponse` — we only care about `profile`
/// here. The user identity (id, email) comes from Firebase, not this DTO.
private struct MeEnvelope: Decodable {
    let profile: ProfileResponse?
}

/// Mirror of the backend `UpdateMeRequest`. Default-nil fields skip the
/// JSON encoding — the backend treats omitted fields as "leave alone".
struct UpdateMeRequest: Encodable {
    var displayName: String? = nil
    var timezone: String? = nil
    var reminderHour: Int? = nil
    var onboardingCompleted: Bool? = nil
    var clearReminderHour: Bool? = nil
    var birthDate: String? = nil
    var birthTime: String? = nil
    var birthPlace: String? = nil
    var clearBirthDetails: Bool? = nil
    var country: String? = nil
    var state: String? = nil
    var city: String? = nil
}

// MARK: - ProfileService

/// Owns the user's `/me` profile state, drives the required-data gate
/// pattern, and is the single source of truth for any UI that needs to read
/// or mutate profile fields.
///
/// Lifecycle:
/// - On Firebase sign-in: waits for `AuthService` to finish its initial
///   profile sync (which lazy-creates the backend `Profile` row), then
///   hydrates from cache and fetches `/me`.
/// - On sign-out: clears in-memory state and the cached profile.
///
/// Consumers read `loadState` to know whether to render a splash, a gate, or
/// the main app, and `requiredGate` to know which gate (if any) is currently
/// blocking the user.
@MainActor
final class ProfileService: ObservableObject {
    static let shared = ProfileService()

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    @Published private(set) var profile: ProfileResponse?
    @Published private(set) var loadState: LoadState = .idle

    /// The first unsatisfied gate, in priority order. `nil` when every gate
    /// passes — that's the signal to mount `MainTabView`.
    ///
    /// When `profile` is nil (defensive — should never happen post-load
    /// because `syncTimezone` lazy-creates the row), evaluate gates against
    /// an empty profile so they all fire. Better to over-prompt than slip
    /// the user through to the main app with missing data.
    var requiredGate: (any RequiredGate)? {
        let snapshot = profile ?? ProfileResponse.empty
        return Self.gates.first { !$0.isSatisfied(snapshot) }
    }

    /// Position of the active gate in the registered array (0-based).
    /// Drives the wizard chrome's "STEP N OF M" counter and progress dots.
    /// Returns 0 when no gate is active.
    var requiredGateIndex: Int {
        guard let gate = requiredGate else { return 0 }
        return Self.gates.firstIndex(where: { $0.id == gate.id }) ?? 0
    }

    /// Total number of gates the app *defines* — every step the user might
    /// see across their lifetime as a member, not just unfinished ones.
    var totalGates: Int { Self.gates.count }

    /// Ordered list of gates. Add new gates here — earlier gates take
    /// priority and run first. Each gate is one self-contained file in
    /// `Services/Gates/`. The order also drives the wizard step numbers.
    private static let gates: [any RequiredGate] = [
        DisplayNameGate(),
        LocationGate(),
        // Future gates land here, e.g. BirthDetailsGate(), TimezoneConfirmGate(), ...
    ]

    private static let cacheKey = "profile.cache.v1"

    /// Tracks the Firebase user ID we last loaded for. Lets us skip
    /// re-fetching on token refresh while still picking up account switches.
    private var lastLoadedUserId: String?

    /// Set to true once we've stamped `OnboardingCompleted = true` for this
    /// session — prevents repeated PATCHes when gates pass.
    private var didStampOnboardingCompleted = false

    private var cancellables = Set<AnyCancellable>()
    private var didBind = false

    private init() {
        // Hydrate from cache so cold launches with no network can still
        // skip the splash if all gates were already satisfied last time.
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(ProfileResponse.self, from: data) {
            self.profile = cached
            self.loadState = .loaded
        }
    }

    // MARK: - Auth wiring

    /// Subscribe to AuthService and react to sign-in / sign-out.
    /// Idempotent — safe to call from `.task` modifiers that may re-fire.
    func bind(to auth: AuthService) {
        guard !didBind else { return }
        didBind = true
        auth.$user
            .removeDuplicates(by: { $0?.uid == $1?.uid })
            .sink { [weak self] user in
                guard let self else { return }
                Task { @MainActor in
                    if let user {
                        await self.handleSignIn(userId: user.uid, auth: auth)
                    } else {
                        self.handleSignOut()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func handleSignIn(userId: String, auth: AuthService) async {
        // Don't re-fetch if we're already loaded for this user (token
        // refreshes fire the auth listener too — guard against spam).
        if lastLoadedUserId == userId, profile != nil, case .loaded = loadState {
            return
        }
        lastLoadedUserId = userId
        // AuthService.syncTimezone() lazy-creates the backend Profile on first
        // sign-in. Wait for that so /me doesn't race ahead and 404.
        await auth.awaitInitialSync()
        await load()
    }

    private func handleSignOut() {
        profile = nil
        loadState = .idle
        lastLoadedUserId = nil
        didStampOnboardingCompleted = false
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
    }

    // MARK: - Network

    /// Fetch `/me` and replace local state. Public so callers can retry
    /// after a load failure.
    func load() async {
        loadState = .loading
        do {
            let envelope: MeEnvelope = try await ApiService.shared.get("/me")
            apply(envelope.profile)
            loadState = .loaded
            await stampOnboardingCompletedIfReady()
        } catch {
            // 401 → expired token. AuthService's listener will flip the user
            // to nil shortly; the orchestrator will return to LoginView.
            // We surface a generic message; the failed view offers retry +
            // sign-out so the user is never trapped.
            if let api = error as? ApiError, api.is401 {
                AppLogger.shared.error("ProfileService", "401 loading /me — token expired")
                loadState = .failed(message: "Your session expired. Please sign in again.")
                AuthService.shared.signOut()
            } else if !error.isCancellation {
                AppLogger.shared.error("ProfileService", "Failed to load /me: \(error.localizedDescription)")
                loadState = .failed(message: friendlyMessage(for: error))
            }
        }
    }

    /// Apply a profile diff via `PATCH /me` and refresh local state. Called
    /// by gate views when the user submits their data.
    func update(_ patch: UpdateMeRequest) async throws {
        do {
            let _: EmptyResponse = try await ApiService.shared.patch("/me", body: patch)
        } catch {
            if let api = error as? ApiError, api.is401 {
                AuthService.shared.signOut()
            }
            throw error
        }
        await load()
    }

    /// Convenience for the `DisplayNameGate` — single-field update with
    /// trimming and empty-string guarding.
    func setDisplayName(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await update(UpdateMeRequest(displayName: trimmed))
    }

    // MARK: - Internals

    private func apply(_ next: ProfileResponse?) {
        profile = next
        if let next, let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        } else if next == nil {
            UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        }
    }

    /// Once every gate is satisfied for the first time, flip the backend's
    /// `OnboardingCompleted` flag so analytics/segmentation downstream has a
    /// clean "user finished onboarding" signal that's independent of the
    /// per-field gates.
    private func stampOnboardingCompletedIfReady() async {
        guard !didStampOnboardingCompleted,
              let profile,
              !profile.onboardingCompleted,
              requiredGate == nil
        else { return }
        didStampOnboardingCompleted = true
        do {
            try await update(UpdateMeRequest(onboardingCompleted: true))
        } catch {
            // Non-fatal — we'll try again on next launch. Don't block.
            didStampOnboardingCompleted = false
            AppLogger.shared.info("ProfileService", "OnboardingCompleted stamp deferred: \(error.localizedDescription)")
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline. Reconnect and try again."
            case .timedOut:
                return "The server took too long to respond. Try again in a moment."
            default:
                return "We couldn't reach the server. Try again."
            }
        }
        return "We couldn't load your profile. Try again."
    }
}
