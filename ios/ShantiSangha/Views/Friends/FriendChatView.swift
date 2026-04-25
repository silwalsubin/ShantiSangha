import SwiftUI
import PhotosUI

/// 1:1 chat with a friend — text, image, and voice messages.
struct FriendChatView: View {
    let friend: FriendSummary
    @StateObject private var vm: FriendChatViewModel
    @State private var draft: String = ""
    @State private var photoSelection: PhotosPickerItem?
    @State private var showRecorder = false
    @State private var showEndConfirm = false
    @Environment(\.dismiss) private var dismiss

    init(friend: FriendSummary) {
        self.friend = friend
        _vm = StateObject(wrappedValue: FriendChatViewModel(
            friendshipId: friend.friendshipId,
            friendUserId: friend.friendUserId,
            friendDisplayName: friend.displayName))
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList

            composer
                .background(Color.sacredBg)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle(friend.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("End friendship", role: .destructive) {
                        showEndConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.sacredGold)
                }
            }
        }
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
        .task { await vm.refresh() }
        .onChange(of: photoSelection) { _, newItem in
            guard let newItem else { return }
            Task { await sendPickedImage(newItem) }
        }
        .sheet(isPresented: $showRecorder) {
            VoiceRecorderSheet { data, contentType, durationMs in
                Task { await vm.sendVoice(data: data, contentType: contentType, durationMs: durationMs) }
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if vm.loading && vm.messages.isEmpty {
                    ProgressView().padding(.top, SacredSpacing.xl)
                } else if vm.messages.isEmpty {
                    SacredEmptyState(
                        icon: "ellipsis.message",
                        title: "Say hello.",
                        subtitle: "Your messages stay between the two of you."
                    )
                    .padding(.top, SacredSpacing.xl)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(vm.messages) { msg in
                            MessageBubble(message: msg, fromFriend: vm.isFromFriend(msg))
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, SacredSpacing.m)
                    .padding(.vertical, SacredSpacing.m)
                }

                if let err = vm.errorMessage {
                    Text(err)
                        .font(.sacredSmall)
                        .foregroundColor(.sacredRed)
                        .padding(.horizontal, SacredSpacing.m)
                }
            }
            .onChange(of: vm.messages.last?.id) { _, _ in
                if let last = vm.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $photoSelection, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(.sacredGold)
                    .frame(width: 38, height: 38)
            }

            Button { showRecorder = true } label: {
                Image(systemName: "mic")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(.sacredGold)
                    .frame(width: 38, height: 38)
            }

            TextField("Message", text: $draft, axis: .vertical)
                .font(.sacredText)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.sacredBgCard))

            Button {
                let text = draft
                draft = ""
                Task { await vm.sendText(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(canSend ? .sacredGold : .sacredMutedLight)
            }
            .disabled(!canSend || vm.sending)
        }
        .padding(.horizontal, SacredSpacing.m)
        .padding(.vertical, SacredSpacing.s)
        .background(Color.sacredBg)
        .overlay(Rectangle().fill(Color.sacredGold.opacity(0.1)).frame(height: 0.5), alignment: .top)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendPickedImage(_ item: PhotosPickerItem) async {
        defer { photoSelection = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await vm.sendImage(data: data, contentType: "image/jpeg")
    }

    private func endFriendship() async {
        do {
            try await FriendsAPI.endFriendship(friend.friendshipId)
            NotificationCenter.default.post(name: .friendsUpdated, object: nil)
            dismiss()
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }
}

private struct MessageBubble: View {
    let message: FriendMessage
    let fromFriend: Bool

    var body: some View {
        HStack {
            if !fromFriend { Spacer(minLength: 32) }

            VStack(alignment: fromFriend ? .leading : .trailing, spacing: 2) {
                content
                Text(timeLabel)
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
            }

            if fromFriend { Spacer(minLength: 32) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch message.kind {
        case .text:
            Text(message.body ?? "")
                .font(.sacredText)
                .foregroundColor(fromFriend ? .sacredText : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        case .image:
            if let urlStr = message.mediaUrl, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: ProgressView().frame(width: 200, height: 200)
                    case .success(let image): image.resizable().scaledToFit()
                    case .failure: Image(systemName: "photo").foregroundColor(.sacredMuted)
                    @unknown default: EmptyView()
                    }
                }
                .frame(maxWidth: 240, maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        case .voice:
            VoicePlayerView(url: message.mediaUrl, durationMs: message.durationMs, fromFriend: fromFriend)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private var bubbleBackground: some View {
        Group {
            if fromFriend {
                Color.sacredBgCard
            } else {
                LinearGradient.sacredGoldShinyVertical
            }
        }
    }

    private var timeLabel: String {
        guard let d = FriendsDates.parse(message.sentAt) else { return "" }
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: d)
    }
}
