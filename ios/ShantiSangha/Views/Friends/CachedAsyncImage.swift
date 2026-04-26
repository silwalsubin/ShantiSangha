import SwiftUI

/// AsyncImage replacement that consults `ChatMediaCache` first.
/// Renders from a local file on cache hit (instant, works offline);
/// downloads + caches on miss; falls back to a placeholder if both
/// the cache and the network are unavailable.
///
/// Why not stick with stock AsyncImage: AsyncImage relies on
/// URLSession's default cache, which is in-memory + small disk
/// (~50MB) with no per-key control and weak persistence guarantees
/// across app launches. Our cache is keyed on stable message ids
/// and survives presigned-URL rotation.
struct CachedAsyncImage: View {
    let messageId: UUID
    let remoteUrl: URL

    @State private var localURL: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if let localURL, let img = UIImage(contentsOfFile: localURL.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            } else if failed {
                Image(systemName: "photo")
                    .foregroundColor(.sacredMuted)
            } else {
                ProgressView()
                    .frame(width: 200, height: 200)
            }
        }
        .task(id: messageId) {
            // Already have the local file — skip the actor hop.
            if localURL != nil { return }
            if let url = await ChatMediaCache.shared.cachedURL(
                messageId: messageId,
                remoteUrl: remoteUrl) {
                localURL = url
            } else {
                failed = true
            }
        }
    }
}
