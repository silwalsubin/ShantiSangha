import Foundation
import UIKit
import AVFoundation

/// Disk cache + offline store for connection keepsakes.
///
/// Two storage tiers:
/// - **Thumbnails** live in `Library/Caches/...` so iOS can evict them
///   under disk pressure — they can always be regenerated from the
///   presigned source URL.
/// - **Offline-saved full content** lives in
///   `Library/Application Support/...` so the bytes survive across
///   launches and aren't reaped by the system. This matches the
///   "Available offline" model in Dropbox / Google Drive.
///
/// Identity is the attachment's stable UUID — presigned download URLs
/// rotate every list call, so keying off the URL would miss the cache
/// constantly. The file extension is preserved so QuickLook / system
/// openers pick the right handler when the user taps a saved file.
@MainActor
final class AttachmentCache: ObservableObject {
    static let shared = AttachmentCache()

    /// Set of attachment IDs that have a full copy on disk. Published so
    /// SwiftUI views can react (offline indicator, toggle state) without
    /// each tile polling the filesystem on every render.
    @Published private(set) var offlineIds: Set<UUID> = []

    /// Memory mirror of the on-disk thumbnail cache. NSCache is enough —
    /// disk is the source of truth, this just dodges a round trip on
    /// re-renders within a session.
    private let thumbnailMemory = NSCache<NSString, UIImage>()

    private let fm = FileManager.default

    private lazy var thumbnailsDir: URL = {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("keepsakes/thumbnails", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private lazy var offlineDir: URL = {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("keepsakes/offline", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // Files in Application Support default to being included in
        // iCloud/iTunes backups — opt out for cache content the user
        // can re-download.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = dir
        try? mutable.setResourceValues(values)
        return dir
    }()

    private init() {
        thumbnailMemory.countLimit = 200
        rebuildOfflineIndex()
    }

    // MARK: - Thumbnails

    /// Synchronous lookup — returns the cached thumbnail if it exists in
    /// memory or on disk, else nil. Callers should fall back to
    /// downloading via `loadThumbnail(for:)`.
    func cachedThumbnail(for attachmentId: UUID) -> UIImage? {
        let key = attachmentId.uuidString as NSString
        if let memory = thumbnailMemory.object(forKey: key) {
            return memory
        }
        let path = thumbnailsDir.appendingPathComponent("\(attachmentId.uuidString).jpg")
        guard let data = try? Data(contentsOf: path),
              let image = UIImage(data: data) else { return nil }
        thumbnailMemory.setObject(image, forKey: key)
        return image
    }

    /// Fetch the thumbnail, populating the cache. For images we pull
    /// the source URL once and downscale; for videos we use any locally
    /// saved copy (offline file) and extract a frame, otherwise return
    /// nil so the view falls back to a placeholder. We don't pull a
    /// whole video over the network just to make a thumbnail — that's
    /// what offline-save unlocks.
    func loadThumbnail(for attachment: ConnectionAttachment) async -> UIImage? {
        if let cached = cachedThumbnail(for: attachment.id) { return cached }

        let isImage = attachment.contentType.hasPrefix("image/")
        let isVideo = attachment.contentType.hasPrefix("video/")

        if isImage, let url = URL(string: attachment.downloadUrl) {
            return await fetchAndCacheImageThumbnail(from: url, for: attachment.id)
        }
        if isVideo, let localURL = offlineFileURL(for: attachment) {
            return await extractAndCacheVideoThumbnail(from: localURL, for: attachment.id)
        }
        return nil
    }

    private func fetchAndCacheImageThumbnail(
        from url: URL,
        for attachmentId: UUID
    ) async -> UIImage? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let image = UIImage(data: data) else { return nil }

            let downscaled = image.downscaled(toMaxDimension: 480)
            persistThumbnail(downscaled, for: attachmentId)
            return downscaled
        } catch {
            return nil
        }
    }

    private func extractAndCacheVideoThumbnail(
        from url: URL,
        for attachmentId: UUID
    ) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        do {
            let cgImage = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image
            let image = UIImage(cgImage: cgImage)
            let downscaled = image.downscaled(toMaxDimension: 480)
            persistThumbnail(downscaled, for: attachmentId)
            return downscaled
        } catch {
            return nil
        }
    }

    /// Public seed path used by the optimistic upload flow — caches the
    /// already-decoded local image as the thumbnail for an attachment id
    /// so the grid never has to round-trip to S3 just to redraw what the
    /// user already saw locally.
    func cacheThumbnail(_ image: UIImage, for attachmentId: UUID) {
        persistThumbnail(image, for: attachmentId)
    }

    private func persistThumbnail(_ image: UIImage, for attachmentId: UUID) {
        let key = attachmentId.uuidString as NSString
        thumbnailMemory.setObject(image, forKey: key)
        if let data = image.jpegData(compressionQuality: 0.8) {
            let path = thumbnailsDir.appendingPathComponent("\(attachmentId.uuidString).jpg")
            try? data.write(to: path, options: .atomic)
        }
    }

    // MARK: - Offline full content

    func isOffline(_ attachmentId: UUID) -> Bool {
        offlineIds.contains(attachmentId)
    }

    func offlineFileURL(for attachment: ConnectionAttachment) -> URL? {
        let path = offlineDir.appendingPathComponent(filename(for: attachment))
        return fm.fileExists(atPath: path.path) ? path : nil
    }

    /// Downloads the full attachment to the offline store. After
    /// success, video thumbnails get extracted from the local copy so
    /// the grid stops showing the placeholder gradient.
    func saveOffline(_ attachment: ConnectionAttachment) async throws {
        guard let url = URL(string: attachment.downloadUrl) else {
            throw ApiError.invalidURL
        }
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            try? fm.removeItem(at: tempURL)
            throw ApiError.invalidResponse
        }

        let dest = offlineDir.appendingPathComponent(filename(for: attachment))
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: tempURL, to: dest)

        offlineIds.insert(attachment.id)

        // For videos, now that we have local bytes, generate the tile
        // thumbnail eagerly so the next render shows a real frame.
        if attachment.contentType.hasPrefix("video/") {
            _ = await extractAndCacheVideoThumbnail(from: dest, for: attachment.id)
        }
    }

    func removeOffline(_ attachment: ConnectionAttachment) {
        let path = offlineDir.appendingPathComponent(filename(for: attachment))
        try? fm.removeItem(at: path)
        offlineIds.remove(attachment.id)
    }

    /// Removes the row's traces — both the offline copy (if any) and
    /// the cached thumbnail. Called when the user deletes the
    /// attachment server-side.
    func purge(_ attachment: ConnectionAttachment) {
        removeOffline(attachment)
        let thumb = thumbnailsDir.appendingPathComponent("\(attachment.id.uuidString).jpg")
        try? fm.removeItem(at: thumb)
        thumbnailMemory.removeObject(forKey: attachment.id.uuidString as NSString)
    }

    // MARK: - Internals

    /// `{uuid}.{ext}` so QuickLook / Files / system handlers identify
    /// the format from the suffix. The original filename can carry
    /// odd characters, so we keep our own simple form.
    private func filename(for attachment: ConnectionAttachment) -> String {
        let ext = (attachment.fileName as NSString).pathExtension
        if ext.isEmpty { return attachment.id.uuidString }
        return "\(attachment.id.uuidString).\(ext)"
    }

    /// Walks the offline directory and seeds `offlineIds` from the
    /// {uuid}.{ext} filenames. Called once at init so the published
    /// state matches what's actually on disk after a launch.
    private func rebuildOfflineIndex() {
        guard let contents = try? fm.contentsOfDirectory(atPath: offlineDir.path) else { return }
        var ids = Set<UUID>()
        for name in contents {
            // Strip extension, then parse the UUID stem.
            let stem = (name as NSString).deletingPathExtension
            if let uuid = UUID(uuidString: stem) {
                ids.insert(uuid)
            }
        }
        offlineIds = ids
    }
}

private extension UIImage {
    /// Aspect-fit downscale so the longer edge fits within `max`.
    /// Returns the original image when it's already smaller — no
    /// point pre-shrinking already-tiny thumbnails.
    func downscaled(toMaxDimension max: CGFloat) -> UIImage {
        let w = size.width
        let h = size.height
        let longest = Swift.max(w, h)
        if longest <= max { return self }
        let scale = max / longest
        let target = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
