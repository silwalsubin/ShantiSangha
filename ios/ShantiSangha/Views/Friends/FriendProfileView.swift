import SwiftUI

/// Per-friend profile screen reachable by tapping the chat header. Shows
/// the friend's public data (avatar / display name / location) plus two
/// viewer-private fields the friend can never see: a nickname (replaces
/// the friend's display name everywhere on this user's end) and a
/// freeform private notes textarea. Also owns the End Friendship action
/// — moved here from the chat's `...` menu so the chat header stays
/// focused on the conversation itself.
struct FriendProfileView: View {
    let friendshipId: UUID
    @ObservedObject var vm: FriendsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var nicknameDraft: String = ""
    @State private var notesDraft: String = ""
    @State private var savingNickname = false
    @State private var savingNotes = false
    @State private var saveError: String?
    @State private var showEndConfirm = false
    @State private var ending = false

    /// Pull from the live `vm.friends` array so an in-place update from
    /// `vm.updateAnnotations` reflects without re-pushing the view.
    private var friend: FriendSummary? {
        vm.friends.first(where: { $0.friendshipId == friendshipId })
    }

    var body: some View {
        ScrollView {
            if let friend {
                VStack(spacing: SacredSpacing.l) {
                    header(friend)
                    nicknameSection
                    notesSection
                    endFriendshipSection(friend)
                }
                .padding(.horizontal, SacredSpacing.m)
                .padding(.vertical, SacredSpacing.l)
            } else {
                // The friend disappeared from the local list (ended from
                // another device, etc.). Pop instead of stranding the user.
                Color.clear.onAppear { dismiss() }
            }
        }
        .background(SacredBackground().ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            guard let friend else { return }
            nicknameDraft = friend.nickname ?? ""
            notesDraft = friend.privateNotes ?? ""
        }
    }

    // MARK: - Header

    private func header(_ friend: FriendSummary) -> some View {
        VStack(spacing: SacredSpacing.s) {
            SacredAvatar(
                displayName: friend.displayName,
                avatarUrl: friend.avatarUrl,
                size: 120)

            Text(friend.displayName)
                .font(.sacredHeading)
                .foregroundColor(.sacredText)
                .multilineTextAlignment(.center)

            if let loc = friend.locationString {
                Text(loc)
                    .font(.sacredText)
                    .foregroundColor(.sacredMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SacredSpacing.m)
    }

    // MARK: - Nickname

    private var nicknameSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("NICKNAME")

            SacredListCard {
                HStack(spacing: 10) {
                    TextField("Add a nickname", text: $nicknameDraft)
                        .font(.sacredText)
                        .foregroundColor(.sacredText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .submitLabel(.done)
                        .onSubmit { Task { await saveNickname() } }

                    if savingNickname {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.sacredGold)
                            .padding(.trailing, 14)
                    }
                }
            }

            Text("Replaces their name everywhere on your end.")
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Private notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("PRIVATE NOTES")

            SacredListCard {
                ZStack(alignment: .topLeading) {
                    if notesDraft.isEmpty {
                        Text("What you notice about them.")
                            .font(.sacredText)
                            .foregroundColor(.sacredMutedLight)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 18)
                    }

                    TextEditor(text: $notesDraft)
                        .font(.sacredText)
                        .foregroundColor(.sacredText)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(minHeight: 120)
                        .onChange(of: notesDraft) { _, _ in scheduleNotesSave() }
                }

                if savingNotes {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                            .tint(.sacredGold)
                        Text("Saving…")
                            .font(.sacredMicro)
                            .foregroundColor(.sacredMuted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
            }

            Text("Only you can see this.")
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - End friendship

    private func endFriendshipSection(_ friend: FriendSummary) -> some View {
        VStack(spacing: SacredSpacing.s) {
            if let saveError {
                Text(saveError)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SacredSpacing.s)
            }

            Button(role: .destructive) {
                showEndConfirm = true
            } label: {
                HStack {
                    if ending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.sacredRed)
                    }
                    Text(ending ? "Ending…" : "End friendship")
                        .font(.sacredText)
                        .foregroundColor(.sacredRed)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.sacredRed.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(ending)
        }
        .padding(.top, SacredSpacing.l)
        .confirmationDialog(
            "End friendship with \(friend.displayName)?",
            isPresented: $showEndConfirm,
            titleVisibility: .visible
        ) {
            Button("End friendship", role: .destructive) {
                Task { await endFriendship() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your message thread and any media will be deleted on both sides. This can't be undone.")
        }
    }

    // MARK: - Save flow

    private func saveNickname() async {
        guard let friend else { return }
        let trimmed = nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = friend.nickname ?? ""
        if trimmed == original { return }

        savingNickname = true
        defer { savingNickname = false }

        do {
            if trimmed.isEmpty {
                _ = try await vm.updateAnnotations(friendshipId: friendshipId, clearNickname: true)
            } else {
                _ = try await vm.updateAnnotations(friendshipId: friendshipId, nickname: trimmed)
            }
            saveError = nil
        } catch {
            saveError = "Couldn't save. Try again."
        }
    }

    private func scheduleNotesSave() {
        let snapshot = notesDraft
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            // Only commit if the draft hasn't changed since we scheduled —
            // each keystroke schedules a new save and the latest wins.
            if snapshot == notesDraft {
                await saveNotes()
            }
        }
    }

    private func saveNotes() async {
        guard let friend else { return }
        let original = friend.privateNotes ?? ""
        if notesDraft == original { return }

        savingNotes = true
        defer { savingNotes = false }

        do {
            if notesDraft.isEmpty {
                _ = try await vm.updateAnnotations(friendshipId: friendshipId, clearPrivateNotes: true)
            } else {
                _ = try await vm.updateAnnotations(friendshipId: friendshipId, privateNotes: notesDraft)
            }
            saveError = nil
        } catch {
            saveError = "Couldn't save. Try again."
        }
    }

    private func endFriendship() async {
        ending = true
        defer { ending = false }
        do {
            try await FriendsAPI.endFriendship(friendshipId)
            await vm.refresh()
            dismiss()
            // Pop the chat behind us too — the dismiss closure on the
            // chat view picks up the missing friendshipId via vm.friends
            // and unwinds.
        } catch {
            saveError = "Couldn't end the friendship. Try again."
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.sacredSectionLabel)
            .foregroundColor(.sacredLabel)
            .padding(.horizontal, 4)
    }
}
