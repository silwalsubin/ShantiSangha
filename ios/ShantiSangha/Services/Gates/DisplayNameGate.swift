import SwiftUI

/// First gate — collects the name the user wants to be called. Distinct
/// from the Google account name so the user isn't stuck with whatever
/// shows up in their Firebase profile.
struct DisplayNameGate: RequiredGate {
    let id = "display_name"
    let title = "What should we call you?"
    let subtitle: String? = "This is the name you'll see on Home and that friends will see when you connect."

    func isSatisfied(_ profile: ProfileResponse) -> Bool {
        let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !name.isEmpty
    }

    @MainActor func makeBody() -> AnyView {
        AnyView(DisplayNameGateBody())
    }
}
