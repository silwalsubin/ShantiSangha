import UIKit
import UniformTypeIdentifiers
import ImageIO

/// Share Extension entry point.
///
/// No UI — we silently harvest the shared text (and URL / image
/// breadcrumbs), drop it in the App Group container, jump to the main
/// app via `shantisangha://share`, and complete the request. The main
/// app's chat composer pre-fills from that container so the user can
/// edit before sending.
final class ShareViewController: UIViewController {

    private static let appGroup = "group.com.shantisangha.app"
    private static let pendingKey = "share.pendingText"
    private static let pendingDateKey = "share.pendingDate"
    // Media hand-off: the image is copied into the App Group container and
    // its filename + content type are left in defaults for the main app
    // (DeepLinkRouter) to drain and route into a connection's chat.
    private static let pendingMediaNameKey = "share.pendingMediaName"
    private static let pendingMediaTypeKey = "share.pendingMediaType"
    private static let pendingMediaDateKey = "share.pendingMediaDate"
    private static let inboxDir = "SharedInbox"
    private static let openURL = URL(string: "shantisangha://share")!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        harvest { [weak self] payload in
            guard let self else { return }
            switch payload {
            case .image(let data):
                self.persistMedia(data: data, contentType: "image/jpeg")
            case .text(let text):
                self.persist(text: text)
            case .none:
                break
            }
            self.openContainingApp()
            // Tear the extension down only AFTER the host has had a beat
            // to action the open. Completing immediately cancels the
            // pending app launch — that's why it "closed doing nothing."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }

    // MARK: - Harvest

    private enum SharePayload {
        case image(Data)
        case text(String)
        case none
    }

    /// Decides what was shared. An image takes priority — the main app
    /// routes it to a connection's chat. Otherwise we fall back to the
    /// existing text path (URL > plain text > text) that pre-fills the
    /// assistant composer.
    private func harvest(_ completion: @escaping (SharePayload) -> Void) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completion(.none)
            return
        }
        let attachments = items.flatMap { $0.attachments ?? [] }
        guard !attachments.isEmpty else {
            completion(.none)
            return
        }

        if let imageProvider = attachments.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }) {
            loadImage(from: imageProvider) { data in
                DispatchQueue.main.async {
                    completion(data.map(SharePayload.image) ?? .none)
                }
            }
            return
        }

        harvestText(attachments, completion: completion)
    }

    private func harvestText(_ attachments: [NSItemProvider],
                             completion: @escaping (SharePayload) -> Void) {
        let group = DispatchGroup()
        var pieces: [String] = []
        let lock = NSLock()

        func append(_ value: String?) {
            guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            lock.lock()
            pieces.append(value)
            lock.unlock()
        }

        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    if let url = item as? URL {
                        append(url.absoluteString)
                    } else if let str = item as? String {
                        append(str)
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    append(item as? String)
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
                    append(item as? String)
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            let text = pieces.joined(separator: "\n\n")
            completion(text.isEmpty ? .none : .text(text))
        }
    }

    /// Loads the shared image and returns downsampled JPEG bytes.
    ///
    /// CRITICAL: a share extension has a tiny memory budget (~120 MB, often
    /// killed sooner). Fully decoding a modern photo into a `UIImage` and
    /// re-encoding it blows that budget and the OS jetsam-kills the process
    /// — which looks exactly like a crash that dumps the user back to the
    /// host app. So we never decode the full image: ImageIO produces a
    /// downsampled thumbnail straight from the source bytes/URL with a
    /// bounded memory footprint, and we encode that to JPEG.
    private func loadImage(from provider: NSItemProvider, completion: @escaping (Data?) -> Void) {
        // Preferred: raw bytes, downsampled via ImageIO.
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            if let data, let jpeg = Self.downsampledJPEG(fromData: data) {
                completion(jpeg)
                return
            }
            // Fallback: some hosts only vend a file URL or a UIImage.
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                switch item {
                case let url as URL:
                    completion(Self.downsampledJPEG(fromURL: url))
                case let data as Data:
                    completion(Self.downsampledJPEG(fromData: data))
                case let image as UIImage:
                    completion(image.jpegData(compressionQuality: 0.82))
                default:
                    completion(nil)
                }
            }
        }
    }

    /// Max edge for the downsample. Chat photos don't need full-res, and
    /// staying small keeps the extension well under its memory ceiling.
    private static let maxPixel: CGFloat = 2048

    private static func downsampledJPEG(fromURL url: URL) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL,
                                                   [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return downsampledJPEG(from: src)
    }

    private static func downsampledJPEG(fromData data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData,
                                                    [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return downsampledJPEG(from: src)
    }

    private static func downsampledJPEG(from src: CGImageSource) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // respect EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, thumb,
                                   [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    // MARK: - Hand-off

    private func persist(text: String) {
        guard let defaults = UserDefaults(suiteName: Self.appGroup) else { return }
        defaults.set(text, forKey: Self.pendingKey)
        defaults.set(Date(), forKey: Self.pendingDateKey)
    }

    private func persistMedia(data: Data, contentType: String) {
        guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup),
              let defaults = UserDefaults(suiteName: Self.appGroup) else { return }

        let inbox = container.appendingPathComponent(Self.inboxDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        let filename = "share-\(UUID().uuidString).jpg"
        do {
            try data.write(to: inbox.appendingPathComponent(filename), options: .atomic)
            defaults.set(filename, forKey: Self.pendingMediaNameKey)
            defaults.set(contentType, forKey: Self.pendingMediaTypeKey)
            defaults.set(Date(), forKey: Self.pendingMediaDateKey)
        } catch {
            // If the copy fails there's nothing to route — fall through
            // silently; the main app simply won't see a pending media.
        }
    }

    /// Share extensions can't reach `UIApplication.shared`, so we walk
    /// the responder chain to the `UIApplication` living in the extension
    /// process and call the modern `open(_:options:completionHandler:)`.
    /// Falls back to the legacy `openURL:` selector for hosts where the
    /// application isn't found in the chain.
    private func openContainingApp() {
        var responder: UIResponder? = self
        while let current = responder {
            if let app = current as? UIApplication {
                app.open(Self.openURL, options: [:], completionHandler: nil)
                return
            }
            responder = current.next
        }

        // Legacy fallback.
        let selector = NSSelectorFromString("openURL:")
        responder = self
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: Self.openURL)
                return
            }
            responder = current.next
        }
    }
}
