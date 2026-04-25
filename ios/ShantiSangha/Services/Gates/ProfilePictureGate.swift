import SwiftUI

/// Third gate — captures a profile picture. Avatars are visible to friends
/// in the Friends list and chat headers; making it required during
/// onboarding ensures every connection starts with a face attached, not a
/// generic placeholder. Gate is satisfied as soon as the backend has a
/// non-empty `AvatarKey` recorded for this user.
struct ProfilePictureGate: RequiredGate {
    let id = "profile_picture"
    let title = "Add a profile picture"
    let subtitle: String? = "Friends will see this on every message you send. Pick something that feels like you."

    func isSatisfied(_ profile: ProfileResponse) -> Bool {
        let key = profile.avatarKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !key.isEmpty
    }

    @MainActor func makeBody() -> AnyView {
        AnyView(ProfilePictureGateBody())
    }
}
