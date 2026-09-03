import SwiftUI
import Contacts
import ContactsUI

/// Shows one person's real iPhone contact card, read live from the address
/// book so it's never a stale copy.
///
/// Unlike the contact *picker*, this does need permission: reading a specific
/// contact means reading the address book. The ask is deliberately deferred to
/// the moment someone taps through to a card — importing a contact never
/// prompts.
struct ContactCardView: UIViewControllerRepresentable {
    let contactIdentifier: String
    /// Called when the card can't be shown, so the caller can surface it and
    /// decide whether the link is worth keeping.
    let onUnavailable: (ContactCardError) -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        // A placeholder until the fetch resolves; the card is pushed in.
        let placeholder = UIViewController()
        placeholder.view.backgroundColor = .clear
        let nav = UINavigationController(rootViewController: placeholder)

        Task {
            do {
                let contact = try await Self.fetchContact(identifier: contactIdentifier)
                await MainActor.run {
                    let card = CNContactViewController(for: contact)
                    card.allowsEditing = false
                    card.allowsActions = true
                    nav.setViewControllers([card], animated: false)
                }
            } catch let error as ContactCardError {
                await MainActor.run { onUnavailable(error) }
            } catch {
                await MainActor.run { onUnavailable(.notFound) }
            }
        }

        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    enum ContactCardError: Error {
        case denied
        case notFound

        var message: String {
            switch self {
            case .denied:
                return "ShantiSangha doesn't have access to your contacts. You can allow it in Settings → Privacy → Contacts."
            case .notFound:
                return "That contact isn't in your phone anymore."
            }
        }
    }

    private static func fetchContact(identifier: String) async throws -> CNContact {
        let store = CNContactStore()

        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            break
        case .notDetermined:
            guard try await store.requestAccess(for: .contacts) else {
                throw ContactCardError.denied
            }
        default:
            throw ContactCardError.denied
        }

        // CNContactViewController refuses to render a contact fetched with a
        // narrower key set than this descriptor asks for.
        let keys = [CNContactViewController.descriptorForRequiredKeys()]
        do {
            return try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
        } catch {
            throw ContactCardError.notFound
        }
    }
}
