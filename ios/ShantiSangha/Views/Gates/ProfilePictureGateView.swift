import SwiftUI

/// Form body for the profile-picture gate. The crop + upload pipeline
/// lives in `AvatarPickerBody`; this wrapper just plugs in the user's
/// own avatar URL and routes the upload to `ProfileService`.
struct ProfilePictureGateBody: View {
    @EnvironmentObject private var profile: ProfileService

    let submitLabel: String
    let onSaved: (() -> Void)?

    init(submitLabel: String = "Continue", onSaved: (() -> Void)? = nil) {
        self.submitLabel = submitLabel
        self.onSaved = onSaved
    }

    var body: some View {
        AvatarPickerBody(
            initialAvatarUrl: profile.profile?.avatarUrl,
            submitLabel: submitLabel,
            upload: { data in try await profile.uploadAvatar(jpegData: data) },
            onSaved: onSaved
        )
    }
}
