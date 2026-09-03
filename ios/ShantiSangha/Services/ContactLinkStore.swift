import Foundation

/// Remembers which iPhone contact a connection was imported from, so their
/// profile can offer a way back to that card.
///
/// Deliberately on-device only. A `CNContact` identifier is scoped to this
/// phone's address book — it wouldn't reliably resolve on another device, so
/// syncing it to the server would store something that can't be trusted
/// elsewhere. It also keeps address-book identifiers out of the backend
/// entirely, which is the quieter choice for a private circle.
enum ContactLinkStore {
    private static let key = "contacts.linkedByConnection"

    private static var map: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func link(connectionId: UUID, contactIdentifier: String) {
        map[connectionId.uuidString] = contactIdentifier
    }

    static func contactIdentifier(for connectionId: UUID) -> String? {
        map[connectionId.uuidString]
    }

    static func unlink(connectionId: UUID) {
        map.removeValue(forKey: connectionId.uuidString)
    }
}
