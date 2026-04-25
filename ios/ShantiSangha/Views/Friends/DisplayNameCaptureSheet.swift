import SwiftUI

/// Compact sheet that captures the user's display name before they can invite
/// a friend. Submits to `PATCH /api/me`. Calls `onComplete(true)` on success.
struct DisplayNameCaptureSheet: View {
    let onComplete: (Bool) -> Void

    @State private var name: String = ""
    @State private var saving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.l) {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                Text("How should friends see you?")
                    .font(.sacredHeading)
                    .foregroundColor(.sacredText)
                Text("Your friends will only ever see this name.")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }

            TextField("Your name", text: $name)
                .font(.sacredText)
                .padding(SacredSpacing.s)
                .background(RoundedRectangle(cornerRadius: SacredRadius.pill).fill(Color.sacredBgCard))

            if let err = errorMessage {
                Text(err)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredRed)
            }

            SacredPrimaryButton(
                "Save & continue",
                style: .commit,
                isDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
                isLoading: saving
            ) { Task { await save() } }

            Spacer()
        }
        .padding(SacredSpacing.l)
        .presentationDetents([.height(360)])
        .background(Color.sacredBg.ignoresSafeArea())
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        saving = true
        defer { saving = false }
        do {
            struct UpdateMeRequest: Encodable { let displayName: String }
            let _: EmptyResponse = try await ApiService.shared.patch("/me", body: UpdateMeRequest(displayName: trimmed))
            onComplete(true)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
