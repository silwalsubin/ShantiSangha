import SwiftUI
import Contacts
import ContactsUI

struct PickedContact {
    let displayName: String
    let birthday: DateComponents?
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
            // returning nil, so ask before touching it.
            let birthday = contact.isKeyAvailable(CNContactBirthdayKey) ? contact.birthday : nil

            // UIKit delivers these callbacks on the main thread; AppLogger is
            // bound to the main actor.
            MainActor.assumeIsolated {
                AppLogger.shared.info(
                    "Contacts",
                    "Picked contact — name: '\(name)', birthday: \(birthday.map { "\($0.month ?? 0)/\($0.day ?? 0)" } ?? "none")")
            }

            isPresenting = false
            onPick?(PickedContact(displayName: name, birthday: birthday))
            onFinish?()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            isPresenting = false
            onFinish?()
        }
    }
}
