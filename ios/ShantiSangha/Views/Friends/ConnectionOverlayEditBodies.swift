import SwiftUI

/// Single-line nickname editor — siblings of `DisplayNameGateBody`,
/// shaped to match the personal account-edit sheet chrome on Home so
/// the per-Connection edit feels native to the existing sheet pattern.
/// Owns its own draft state; persists via `CircleViewModel.updateOverlay`.
struct ConnectionNicknameEditBody: View {
    @ObservedObject var vm: CircleViewModel
    let connectionId: UUID
    let initialValue: String
    let onSaved: () -> Void

    @State private var draft: String = ""
    @State private var saving = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: SacredSpacing.m) {
            TextField("Add a nickname", text: $draft)
                .typingHaptics(for: draft)
                .font(.sacredBody)
                .foregroundColor(.sacredText)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($fieldFocused)
                .padding(.horizontal, SacredSpacing.m)
                .padding(.vertical, 14)
                .luxCardChrome()
                .onSubmit { Task { await submit() } }

            PrivateFootnote("Replaces their name everywhere on your end.")

            if let errorMessage {
                Text(errorMessage)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SacredPrimaryButton(
                "Save",
                style: .commit,
                isDisabled: !changed,
                isLoading: saving
            ) {
                Task { await submit() }
            }

            if !initialValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    Task { await clear() }
                } label: {
                    Text("Remove nickname")
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.sacredRed)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.plain)
                .disabled(saving)
            }
        }
        .onAppear {
            if draft.isEmpty { draft = initialValue }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { fieldFocused = true }
        }
    }

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var changed: Bool {
        trimmed != initialValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() async {
        guard !saving else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            if trimmed.isEmpty {
                _ = try await vm.updateOverlay(connectionId: connectionId, clearNickname: true)
            } else {
                _ = try await vm.updateOverlay(connectionId: connectionId, nickname: trimmed)
            }
            onSaved()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "We couldn't save that. Try again."
        }
    }

    private func clear() async {
        guard !saving else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            _ = try await vm.updateOverlay(connectionId: connectionId, clearNickname: true)
            onSaved()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "We couldn't remove the nickname. Try again."
        }
    }
}

/// Multi-line private notes editor. Same chrome pattern as the
/// nickname body so the two sheets feel like cousins of each other
/// and of the personal account-edit sheets on Home.
struct ConnectionNotesEditBody: View {
    @ObservedObject var vm: CircleViewModel
    let connectionId: UUID
    let initialValue: String
    let onSaved: () -> Void

    @State private var draft: String = ""
    @State private var saving = false
    @State private var errorMessage: String?
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: SacredSpacing.m) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("What you notice about them.")
                        .font(.sacredText)
                        .foregroundColor(.sacredMutedLight)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }
                TextEditor(text: $draft)
                    .typingHaptics(for: draft)
                    .font(.sacredText)
                    .foregroundColor(.sacredText)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($editorFocused)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 200)
            }
            .luxCardChrome()

            PrivateFootnote()

            if let errorMessage {
                Text(errorMessage)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SacredPrimaryButton(
                "Save",
                style: .commit,
                isDisabled: !changed,
                isLoading: saving
            ) {
                Task { await submit() }
            }

            if !initialValue.isEmpty {
                Button {
                    Task { await clear() }
                } label: {
                    Text("Remove notes")
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.sacredRed)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.plain)
                .disabled(saving)
            }
        }
        .onAppear {
            if draft.isEmpty { draft = initialValue }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editorFocused = true }
        }
    }

    private var changed: Bool { draft != initialValue }

    private func submit() async {
        guard !saving else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            if draft.isEmpty {
                _ = try await vm.updateOverlay(connectionId: connectionId, clearPrivateNotes: true)
            } else {
                _ = try await vm.updateOverlay(connectionId: connectionId, privateNotes: draft)
            }
            onSaved()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "We couldn't save that. Try again."
        }
    }

    private func clear() async {
        guard !saving else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            _ = try await vm.updateOverlay(connectionId: connectionId, clearPrivateNotes: true)
            onSaved()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "We couldn't remove the notes. Try again."
        }
    }
}
