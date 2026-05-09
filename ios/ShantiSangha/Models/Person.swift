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

/// Mirror of the backend `ConnectionResponse`. Each row in the user's
/// circle. `messageable` is the boolean the iOS layer uses to gate the
/// chat affordance — true iff `person.userId != nil` AND
/// `friendshipId != nil`. `circles` is the free-form tag set the owner
/// has applied (empty array allowed — no labels yet).
/// Whether a `ConnectionDate` repeats. `yearly` rolls forward each
/// year (birthday, anniversary, day-we-met). `once` pins to its
/// absolute calendar slot (moved cities, started a job).
enum ConnectionDateRecurrence: String, Codable {
    case yearly = "Yearly"
    case once = "Once"
}

/// Mirror of the backend `ConnectionDateResponse`. A single owner-
/// private "important date" attached to a connection — birthday,
/// anniversary, day-we-met, etc. The date string arrives as ISO
/// 'yyyy-MM-dd' from the backend's `DateOnly`.
struct ConnectionDate: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let label: String
    let date: String
    let recurrence: ConnectionDateRecurrence
}

struct Connection: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let ownerUserId: UUID
    let personId: UUID
    let circles: [String]
    let nickname: String?
    let privateNotes: String?
    let friendshipId: UUID?
    let messageable: Bool
    let createdAt: String
    let updatedAt: String
    let person: Person
    let dates: [ConnectionDate]
    let lastMessagePreview: String?
    let lastMessageAt: String?
    let unreadCount: Int

    /// What we render anywhere this connection's name shows up. Falls
    /// back to the Person's display name when no nickname is set.
    var displayLabel: String {
        if let n = nickname?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        return person.displayName
    }

    /// Comma-joined chip text. Empty string when the user hasn't tagged
    /// this connection yet — call sites should hide the chip in that case.
    var circlesLabel: String {
        circles.joined(separator: ", ")
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
    var circles: [String]? = nil
    var nickname: String? = nil
    var privateNotes: String? = nil
    var phoneNumber: String? = nil
    var email: String? = nil
    var country: String? = nil
    var state: String? = nil
    var city: String? = nil
    var address: String? = nil
}

struct UpdateConnectionRequest: Encodable {
    /// nil = leave alone, [] = clear all circles, otherwise replace.
    var circles: [String]? = nil
    var nickname: String? = nil
    var privateNotes: String? = nil
    var clearNickname: Bool? = nil
    var clearPrivateNotes: Bool? = nil
}

struct AddConnectionDateRequest: Encodable {
    let label: String
    let date: String   // ISO 'yyyy-MM-dd'
    let recurrence: ConnectionDateRecurrence
}

struct UpdateConnectionDateRequest: Encodable {
    let label: String
    let date: String
    let recurrence: ConnectionDateRecurrence
}

struct UpdatePersonRequest: Encodable {
    var displayName: String? = nil
    var phoneNumber: String? = nil
    var email: String? = nil
    var country: String? = nil
    var state: String? = nil
    var city: String? = nil
    var address: String? = nil
    var clearPhoneNumber: Bool? = nil
    var clearEmail: Bool? = nil
    var clearCountry: Bool? = nil
    var clearState: Bool? = nil
    var clearCity: Bool? = nil
    var clearAddress: Bool? = nil
}
