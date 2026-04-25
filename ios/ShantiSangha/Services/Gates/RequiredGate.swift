import SwiftUI

/// A piece of profile data the app refuses to proceed without.
///
/// Each concrete gate is a self-contained type — it owns its predicate
/// (when does this gate need to fire?), its copy (title + subtitle), and
/// the form body that captures the data. `ProfileService` keeps an ordered
/// array of gates and returns the first one whose `isSatisfied` is false.
/// When all gates pass, the user lands on `MainTabView`.
///
/// The orchestrator (`RequiredDataGateView`) supplies the shared wizard
/// chrome — page background, step counter, progress dots, sign-out
/// affordance — so each gate only has to render its body. Adding a new
/// gate later is one new file in `Services/Gates/` plus one new view, and
/// one line added to the array in `ProfileService`.
protocol RequiredGate {
    /// Stable identifier used for telemetry and state-restoration. Matches
    /// the backend field name when possible (`display_name`, `location`).
    var id: String { get }

    /// Headline shown by the orchestrator above the gate's body. Imperative
    /// and warm — "What should we call you?", "Where are you?".
    var title: String { get }

    /// One-line supporting copy under the headline. Optional — pass nil
    /// when the title is self-explanatory.
    var subtitle: String? { get }

    /// Returns true when this gate's data requirement is met by the current
    /// profile. The orchestrator skips satisfied gates and fires the first
    /// unsatisfied one.
    func isSatisfied(_ profile: ProfileResponse) -> Bool

    /// The gate's form body (TextField, list, picker, ...) — wrapped by the
    /// orchestrator's wizard chrome. Pull `ProfileService` from
    /// `@EnvironmentObject` to call `profile.update(_:)` on submit.
    @MainActor func makeBody() -> AnyView
}
