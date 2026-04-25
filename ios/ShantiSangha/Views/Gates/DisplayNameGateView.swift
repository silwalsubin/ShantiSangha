import SwiftUI

/// Form body for the display-name gate — TextField + Continue button +
/// inline error. The orchestrator (`RequiredDataGateView`) wraps this with
/// the page background, step counter, title, subtitle, and sign-out link.
struct DisplayNameGateBody: View {
    @EnvironmentObject private var profile: ProfileService
    @EnvironmentObject private var auth: AuthService
    @FocusState private var nameFieldFocused: Bool

    @State private var name: String = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: SacredSpacing.m) {
            TextField("Your name", text: $name)
                .font(.sacredBody)
                .foregroundColor(.sacredText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFieldFocused)
                .padding(.horizontal, SacredSpacing.m)
                .padding(.vertical, 14)
                .luxCardChrome()
                .onSubmit { Task { await submit() } }

            if let errorMessage {
                Text(errorMessage)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SacredPrimaryButton(
                "Continue",
                style: .commit,
                isDisabled: trimmedName.isEmpty,
                isLoading: saving
            ) {
                Task { await submit() }
            }
        }
        .onAppear {
            // Pre-fill with the previously chosen name (if any) or the first
            // word of the Google name as a starting point.
            if name.isEmpty {
                if let existing = profile.profile?.displayName?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !existing.isEmpty {
                    name = existing
                } else if let firstName = auth.user?.displayName?
                    .components(separatedBy: " ").first {
                    name = firstName
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                nameFieldFocused = true
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() async {
        guard !trimmedName.isEmpty, !saving else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            try await profile.setDisplayName(trimmedName)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "We couldn't save that. Try again."
        }
    }
}
