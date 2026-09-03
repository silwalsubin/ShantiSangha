import SwiftUI
import Contacts
import ContactsUI

struct PickedContact {
    let displayName: String
    let birthday: DateComponents?
}

/// Wraps the system contact picker — no permission prompt, since it runs
/// out-of-process and hands back only the one contact the user taps.
/// Shaped like `CameraPicker`: a delegate-backed `UIViewControllerRepresentable`
/// that dismisses itself on pick or cancel.
struct ContactPickerRepresentable: UIViewControllerRepresentable {
    let onPick: (PickedContact) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        // Deliberately NOT setting displayedPropertyKeys: it switches the
        // picker into property-selection mode, where tapping a person drills
        // into a detail card instead of returning them — the whole-contact
        // delegate below then never fires.
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, dismiss: dismiss)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (PickedContact) -> Void
        let dismiss: DismissAction

        init(onPick: @escaping (PickedContact) -> Void, dismiss: DismissAction) {
            self.onPick = onPick
            self.dismiss = dismiss
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName)
                ?? contact.givenName
            // Reading an unfetched key throws an ObjC exception rather than
            // returning nil, so ask before touching it.
            let birthday = contact.isKeyAvailable(CNContactBirthdayKey) ? contact.birthday : nil
            onPick(PickedContact(displayName: name, birthday: birthday))
            dismiss()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            dismiss()
        }
    }
}
