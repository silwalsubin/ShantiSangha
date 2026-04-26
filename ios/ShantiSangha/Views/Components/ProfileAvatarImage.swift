import SwiftUI
import UIKit

/// Cached circular profile image with a calm icon fallback. `AsyncImage`
/// briefly re-renders its placeholder when sheets reopen; this keeps avatars
/// stable once the image has been fetched in the current app session.
struct ProfileAvatarImage: View {
    private static let cache = NSCache<NSURL, UIImage>()

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

        let cached = Self.cachedImage(for: rawUrl)
        _image = State(initialValue: cached)
        _loadedUrl = State(initialValue: cached == nil ? nil : rawUrl)
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

    private static func cachedImage(for rawUrl: String?) -> UIImage? {
        guard let rawUrl, let url = NSURL(string: rawUrl) else { return nil }
        return cache.object(forKey: url)
    }

    private func loadImageIfNeeded() async {
        guard let rawUrl, loadedUrl != rawUrl, let url = URL(string: rawUrl) else {
            if rawUrl == nil {
                image = nil
                loadedUrl = nil
            }
            return
        }

        let cacheKey = url as NSURL
        if let cached = Self.cache.object(forKey: cacheKey) {
            image = cached
            loadedUrl = rawUrl
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let loaded = UIImage(data: data) else { return }
            Self.cache.setObject(loaded, forKey: cacheKey)
            image = loaded
            loadedUrl = rawUrl
        } catch {
            // Keep the icon fallback quiet; the profile remains editable.
        }
    }
}

