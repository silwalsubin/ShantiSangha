import SwiftUI
import UIKit

/// Cached circular profile image with a calm icon fallback. The bytes come
/// from `AvatarImageCache`, which persists avatar images locally by stable
/// object path so rotating presigned URLs do not cause refetches.
struct ProfileAvatarImage: View {
    let rawUrl: String?
    let size: CGFloat
    let borderOpacity: Double
    let borderWidth: CGFloat
    let shadow: Bool

    @State private var image: UIImage?
    @State private var loadedUrl: String?

    init(
        rawUrl: String?,
        size: CGFloat,
        borderOpacity: Double = 0.42,
        borderWidth: CGFloat = 2,
        shadow: Bool = false
    ) {
        self.rawUrl = rawUrl
        self.size = size
        self.borderOpacity = borderOpacity
        self.borderWidth = borderWidth
        self.shadow = shadow
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        // Shared chrome — clip-to-circle, gold ring, optional drop shadow.
        // Defined in `SacredCircularChrome.swift` so the bell button and
        // any future toolbar circle pick up identical geometry without
        // duplicating numbers.
        .sacredCircularChrome(
            borderOpacity: borderOpacity,
            borderWidth: borderWidth,
            shadow: shadow)
        .task(id: rawUrl) {
            await loadImageIfNeeded()
        }
    }

    private var fallback: some View {
        Circle()
            .fill(Color.sacredBgCard.opacity(0.72))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .regular, design: .serif))
                    .foregroundColor(.sacredMuted)
            )
    }

    private func loadImageIfNeeded() async {
        guard let rawUrl, loadedUrl != rawUrl, let url = URL(string: rawUrl) else {
            if rawUrl == nil {
                image = nil
                loadedUrl = nil
            }
            return
        }

        if let loaded = await AvatarImageCache.shared.image(for: url) {
            image = loaded
        }
        loadedUrl = rawUrl
    }
}
