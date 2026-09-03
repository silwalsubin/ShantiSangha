import SwiftUI
import Contacts
import ContactsUI

/// The one detail this feature depends on quietly: without requesting the
/// birthday key up front, `didSelect` hands back a contact with only an
/// identifier and a name — no birthday, no error, it's just absent.
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
        // Without this, the picked CNContact carries no birthday at all.
        picker.displayedPropertyKeys = [CNContactBirthdayKey]
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
            onPick(PickedContact(displayName: name, birthday: contact.birthday))
            dismiss()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            dismiss()
        }
    }
}
