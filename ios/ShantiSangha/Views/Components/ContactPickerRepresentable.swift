import SwiftUI
import UIKit
import Contacts
import ContactsUI

struct PickedContact: Identifiable {
    var id: String { identifier }

    let displayName: String
    let birthday: DateComponents?
    let imageData: Data?
    let phoneNumber: String?
    let email: String?
    /// Identifier of the source contact, so the profile can offer a way back
    /// to their card. Device/iCloud-scoped — see ContactLinkStore.
    let identifier: String
}

extension PickedContact {
    /// "March 4" — a contact's birthday often carries no year, and a birthday
    /// doesn't need one, so this never shows one either.
    var birthdayLabel: String? {
        guard let birthday else { return nil }
        return Self.monthDay.string(from: Self.date(from: birthday))
    }

    /// The same day as "yyyy-MM-dd" for the reminders API. When the contact
    /// has no birth year we substitute one: it's inert downstream, since a
    /// yearly reminder recomputes its countdown from today and ignores the
    /// stored year.
    var birthdayISODate: String? {
        guard let birthday else { return nil }
        return Self.iso.string(from: Self.date(from: birthday))
    }

    /// Their photo, sized for an avatar: 512pt on the long edge at JPEG 0.7,
    /// matching what the avatar picker produces. Contact photos can be several
    /// megabytes; an avatar never needs that.
    var avatarJPEG: Data? {
        guard let imageData, let image = UIImage(data: imageData) else { return nil }
        let maxDimension: CGFloat = 512
        let largest = max(image.size.width, image.size.height)
        guard largest > maxDimension else { return image.jpegData(compressionQuality: 0.7) }

        let scale = maxDimension / largest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }

    private static func date(from components: DateComponents) -> Date {
        var normalized = components
        if normalized.year == nil {
            // Feb 29 needs a leap year or Calendar returns nil.
            normalized.year = (components.month == 2 && components.day == 29) ? 2024 : 2001
        }
        return Calendar(identifier: .gregorian).date(from: normalized) ?? Date()
    }

    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

/// Opens the system contact picker — no permission prompt, since it runs
/// out-of-process and hands back only the one person the user taps.
///
/// Attach with `.background(...)`, not `.sheet(...)`. The picker must be
/// *presented by* a real view controller rather than being SwiftUI sheet
/// content: as a sheet's root its delegate connection doesn't survive, so
/// selecting someone silently closes the picker and the choice is lost.
/// This presents from a zero-size host that lives quietly in the hierarchy.
struct ContactPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (PickedContact) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        // Refresh captures each update so the coordinator never holds a
        // stale closure from an earlier render.
        context.coordinator.onPick = onPick
        context.coordinator.onFinish = { isPresented = false }

        guard isPresented,
              host.view.window != nil,
              host.presentedViewController == nil,
              !context.coordinator.isPresenting
        else { return }

        context.coordinator.isPresenting = true
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        host.present(picker, animated: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var onPick: ((PickedContact) -> Void)?
        var onFinish: (() -> Void)?
        var isPresenting = false

        // The picker dismisses itself on both paths; we only reset our own state.

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName)
                ?? [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            // Reading an unfetched key throws an ObjC exception rather than
            // returning nil, so ask before touching any of these.
            let birthday = contact.isKeyAvailable(CNContactBirthdayKey) ? contact.birthday : nil

            // Full-size first, thumbnail as a fallback — either is plenty
            // once it's been scaled down to avatar size.
            let imageData: Data? = {
                if contact.isKeyAvailable(CNContactImageDataKey), let full = contact.imageData {
                    return full
                }
                if contact.isKeyAvailable(CNContactThumbnailImageDataKey) {
                    return contact.thumbnailImageData
                }
                return nil
            }()

            let phone = contact.isKeyAvailable(CNContactPhoneNumbersKey)
                ? contact.phoneNumbers.first?.value.stringValue
                : nil
            let email = contact.isKeyAvailable(CNContactEmailAddressesKey)
                ? contact.emailAddresses.first?.value as String?
                : nil

            // UIKit delivers these callbacks on the main thread; AppLogger is
            // bound to the main actor.
            MainActor.assumeIsolated {
                AppLogger.shared.info(
                    "Contacts",
                    "Picked contact — name: '\(name)', birthday: \(birthday.map { "\($0.month ?? 0)/\($0.day ?? 0)" } ?? "none"), photo: \(imageData.map { "\($0.count / 1024)KB" } ?? "none"), phone: \(phone == nil ? "none" : "yes"), email: \(email == nil ? "none" : "yes")")
            }

            isPresenting = false
            onPick?(PickedContact(
                displayName: name,
                birthday: birthday,
                imageData: imageData,
                phoneNumber: phone,
                email: email,
                identifier: contact.identifier))
            onFinish?()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            isPresenting = false
            onFinish?()
        }
    }
}
