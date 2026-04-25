import SwiftUI

/// Second gate — captures where the user lives (country / state / city).
/// All three must be set; the gate stays active until the user picks a
/// place via search or "Use my current location".
struct LocationGate: RequiredGate {
    let id = "location"
    let title = "Where are you?"
    let subtitle: String? = "We use this to set your timezone, find friends nearby, and tune what we surface."

    func isSatisfied(_ profile: ProfileResponse) -> Bool {
        let country = profile.country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let state = profile.state?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let city = profile.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !country.isEmpty && !state.isEmpty && !city.isEmpty
    }

    @MainActor func makeBody() -> AnyView {
        AnyView(LocationGateBody())
    }
}
