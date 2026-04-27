import Foundation

/// Mirror of the backend `PersonResponse`. The "who" — biographical
/// data for someone in the user's circle. For linked Persons (UserId
/// set) most fields flow from the user's Profile and are read-only to
/// other viewers; for local Persons (UserId nil) the owner of the
/// Connection owns these fields too.
struct Person: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let userId: UUID?
    let displayName: String
    let birthDate: String?      // ISO 'yyyy-MM-dd' from backend's DateOnly
    let birthTime: String?
    let birthPlace: String?
    let phoneNumber: String?
    let email: String?
    let country: String?
    let state: String?
    let city: String?
    let address: String?
    let avatarKey: String?
    let avatarUrl: String?

    /// Same shape as `UserSearchResult.locationString` — drops empty
    /// fields and joins what's left with commas, returns nil if nothing
    /// is set so the row can omit the location line.
    var locationString: String? {
        let parts = [city, state, country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

enum ConnectionType: String, Codable, CaseIterable, Identifiable {
    case spouse, parent, sibling, child, friend, colleague, other

    var id: String { rawValue }

    /// Display label for the relation chip / picker. `other` is special
    /// — the UI shows the user's `customRelationLabel` instead when set.
    var label: String {
        switch self {
        case .spouse: return "Spouse"
        case .parent: return "Parent"
        case .sibling: return "Sibling"
        case .child: return "Child"
        case .friend: return "Friend"
        case .colleague: return "Colleague"
        case .other: return "Other"
        }
    }
}

/// Mirror of the backend `ConnectionResponse`. Each row in the user's
/// circle. `messageable` is the boolean the iOS layer uses to gate the
/// chat affordance — true iff `person.userId != nil` AND
/// `friendshipId != nil`.
struct Connection: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let ownerUserId: UUID
    let personId: UUID
    let relationType: String
    let customRelationLabel: String?
    let nickname: String?
    let privateNotes: String?
    let friendshipId: UUID?
    let messageable: Bool
    let createdAt: String
    let updatedAt: String
    let person: Person
    let lastMessagePreview: String?
    let lastMessageAt: String?
    let unreadCount: Int

    /// What we render anywhere this connection's name shows up. Falls
    /// back to the Person's display name when no nickname is set.
    var displayLabel: String {
        if let n = nickname?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        return person.displayName
    }

    /// User-facing chip text for the relation type. Custom label wins
    /// when type is 'other' and a label is set; otherwise the enum's
    /// localized label, or the raw string if it's an unknown enum.
    var relationLabel: String {
        if relationType.lowercased() == ConnectionType.other.rawValue,
           let custom = customRelationLabel?.trimmingCharacters(in: .whitespaces),
           !custom.isEmpty {
            return custom
        }
        if let parsed = ConnectionType(rawValue: relationType.lowercased()) {
            return parsed.label
        }
        return relationType.capitalized
    }

    /// Whether the viewer is allowed to edit the underlying Person
    /// fields. Owner of a local Person can; the Person's own user can
    /// (for self-edits); everyone else is read-only.
    func canEditPerson(viewerUserId: UUID?) -> Bool {
        if person.userId == nil { return true }                 // local
        if let v = viewerUserId, person.userId == v { return true } // own profile
        return false
    }
}

struct CreateConnectionRequest: Encodable {
    let displayName: String
    let relationType: String
    var customRelationLabel: String? = nil
    var nickname: String? = nil
    var privateNotes: String? = nil
    var birthDate: String? = nil
    var birthTime: String? = nil
    var birthPlace: String? = nil
    var phoneNumber: String? = nil
    var email: String? = nil
    var country: String? = nil
    var state: String? = nil
    var city: String? = nil
    var address: String? = nil
}

struct UpdateConnectionRequest: Encodable {
    var relationType: String? = nil
    var customRelationLabel: String? = nil
    var nickname: String? = nil
    var privateNotes: String? = nil
    var clearCustomRelationLabel: Bool? = nil
    var clearNickname: Bool? = nil
    var clearPrivateNotes: Bool? = nil
}

struct UpdatePersonRequest: Encodable {
    var displayName: String? = nil
    var birthDate: String? = nil
    var birthTime: String? = nil
    var birthPlace: String? = nil
    var phoneNumber: String? = nil
    var email: String? = nil
    var country: String? = nil
    var state: String? = nil
    var city: String? = nil
    var address: String? = nil
    var clearBirthDate: Bool? = nil
    var clearBirthTime: Bool? = nil
    var clearBirthPlace: Bool? = nil
    var clearPhoneNumber: Bool? = nil
    var clearEmail: Bool? = nil
    var clearCountry: Bool? = nil
    var clearState: Bool? = nil
    var clearCity: Bool? = nil
    var clearAddress: Bool? = nil
}
