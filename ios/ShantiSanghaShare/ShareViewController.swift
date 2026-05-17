import UIKit
import UniformTypeIdentifiers

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
    private static let openURL = URL(string: "shantisangha://share")!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        harvest { [weak self] text in
            guard let self else { return }
            self.persist(text: text)
            self.openContainingApp()
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    // MARK: - Harvest

    /// Walks every attachment on every input item and loads each one's
    /// best representation (URL > plain text > text > image breadcrumb).
    /// All loads run in parallel; the completion fires once they've all
    /// settled.
    private func harvest(_ completion: @escaping (String) -> Void) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completion("")
            return
        }
        let attachments = items.flatMap { $0.attachments ?? [] }
        guard !attachments.isEmpty else {
            completion("")
            return
        }

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
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                // No multimodal chat yet — leave a breadcrumb so the
                // composer at least shows something useful and the user
                // can describe what they shared.
                append("[shared image]")
            }
        }

        group.notify(queue: .main) {
            completion(pieces.joined(separator: "\n\n"))
        }
    }

    // MARK: - Hand-off

    private func persist(text: String) {
        guard let defaults = UserDefaults(suiteName: Self.appGroup) else { return }
        defaults.set(text, forKey: Self.pendingKey)
        defaults.set(Date(), forKey: Self.pendingDateKey)
    }

    /// Share extensions can't call `UIApplication.shared.open` directly.
    /// Walk the responder chain to find a `UIApplication` and invoke
    /// `openURL:` via the Obj-C runtime. This is the long-standing
    /// workaround that still ships in production share extensions.
    private func openContainingApp() {
        var responder: UIResponder? = self
        let selector = NSSelectorFromString("openURL:")
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: Self.openURL)
                return
            }
            responder = current.next
        }
    }
}
