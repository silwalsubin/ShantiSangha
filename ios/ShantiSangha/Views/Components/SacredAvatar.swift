import SwiftUI

/// Single source of truth for avatar rendering across the app.
///
/// Renders the user's photo via `AsyncImage` when an avatar URL is set;
/// falls back to a gold-gradient circle with the default `person.fill`
/// icon otherwise — matching the placeholder treatment used in the
/// onboarding profile-picture gate. Used by FriendsTabView, UserSearchView,
/// UserProfilePreviewSheet, and any future surface that needs to display
/// another user's avatar in a consistent visual style.
///
/// `displayName` is unused by the default rendering today but accepted
/// here so callers can opt in to initials later (e.g., a settings card)
/// without changing their call site.
///
/// `size` scales the entire view (frame + icon font) so a 40-pt list
/// row, 80-pt sheet header, and 120-pt onboarding preview all share the
/// same code path.
struct SacredAvatar: View {
    let displayName: String?
    let avatarUrl: String?
    let size: CGFloat

    @State private var loadedImage: UIImage?

    /// Icon scales with size — at 40 pt avatar we want ~22 pt icon, at
    /// 120 pt we want ~64 pt. Linear ratio works.
    private var iconFontSize: CGFloat {
        max(14, size * 0.55)
    }

    var body: some View {
        ZStack {
            // Gold-gradient placeholder underneath so any frame in
            // which the image hasn't resolved still renders as a warm
            // circle rather than a blank.
            Circle()
                .fill(LinearGradient.sacredGoldShinyVertical)

            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                defaultIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.sacredGoldDark.opacity(0.18), lineWidth: 0.75))
        // Re-fetch when the URL changes (presigned avatars rotate every
        // refresh). Routed through AvatarImageCache so every SacredAvatar
        // for the same URL on screen shares one fetched copy — fixes the
        // bug where the 12pt read-receipt rendered while the 28pt gutter
        // avatar fell into a failed AsyncImage state.
        .task(id: avatarUrl) {
            guard let urlString = avatarUrl,
                  !urlString.isEmpty,
                  let url = URL(string: urlString) else {
                loadedImage = nil
                return
            }
            loadedImage = await AvatarImageCache.shared.image(for: url)
        }
    }

    private var defaultIcon: some View {
        Image(systemName: "person.fill")
            .font(.system(size: iconFontSize, weight: .regular, design: .serif))
            .foregroundColor(.white.opacity(0.9))
    }
}
