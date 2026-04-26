import SwiftUI
import PhotosUI
import UIKit

/// 1:1 chat with a friend — text, image, and voice messages.
struct FriendChatView: View {
    let friend: FriendSummary
    @StateObject private var vm: FriendChatViewModel
    @State private var draft: String = ""
    @State private var photoSelection: PhotosPickerItem?
    @State private var showRecorder = false
    @State private var showEndConfirm = false
    @State private var actionTarget: FriendMessage?
    @State private var imagePreview: PreviewedImage?
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

            typingPill

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
        .confirmationDialog(
            "Message",
            isPresented: actionTargetBinding,
            titleVisibility: .hidden,
            presenting: actionTarget
        ) { target in
            if !target.isDeleted {
                Button("Reply") {
                    vm.beginReply(target)
                }
            }
            if vm.canEdit(target) {
                Button("Edit") {
                    vm.beginEdit(target)
                    draft = target.body ?? ""
                }
            }
            if vm.canDelete(target) {
                Button("Delete", role: .destructive) {
                    Task { await vm.deleteMessage(target) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            await vm.refresh()
            vm.startRealtime()
        }
        .onDisappear { vm.stopRealtime() }
        .onChange(of: photoSelection) { _, newItem in
            guard let newItem else { return }
            Task { await sendPickedImage(newItem) }
        }
        .onChange(of: draft) { _, newValue in
            // Mirror the composer's state into a typing-presence ping —
            // ChatRealtimeClient debounces internally so this is cheap.
            // Skip while in edit mode: editing is local until submit.
            guard vm.editingMessageId == nil else { return }
            Task { await vm.sendTypingState(hasText: !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
        .sheet(isPresented: $showRecorder) {
            VoiceRecorderSheet { data, contentType, durationMs in
                Task { await vm.sendVoice(data: data, contentType: contentType, durationMs: durationMs) }
            }
        }
        .fullScreenCover(item: $imagePreview) { item in
            ChatImageViewer(url: item.url)
        }
    }

    private var actionTargetBinding: Binding<Bool> {
        Binding(
            get: { actionTarget != nil },
            set: { if !$0 { actionTarget = nil } }
        )
    }

    /// Show the friend's avatar only on the first message of a
    /// consecutive run from them — repeating the same avatar on every
    /// bubble becomes visual noise. The slot is still reserved (empty)
    /// on continuation rows so bubbles stay vertically aligned.
    private func shouldShowAvatar(at index: Int) -> Bool {
        let msg = vm.messages[index]
        guard vm.isFromFriend(msg) else { return false }
        if index == 0 { return true }
        let prev = vm.messages[index - 1]
        return prev.senderUserId != msg.senderUserId
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
                        if vm.loadingOlder {
                            ProgressView()
                                .padding(.vertical, SacredSpacing.s)
                        }

                        ForEach(Array(vm.messages.enumerated()), id: \.element.id) { idx, msg in
                            MessageBubble(
                                message: msg,
                                fromFriend: vm.isFromFriend(msg),
                                friendDisplayName: friend.displayName,
                                friendAvatarUrl: friend.avatarUrl,
                                showAvatar: shouldShowAvatar(at: idx),
                                onTapImage: { url in imagePreview = PreviewedImage(url: url) })
                                .id(msg.id)
                                .onLongPressGesture {
                                    if vm.canEdit(msg) || vm.canDelete(msg) {
                                        actionTarget = msg
                                    }
                                }
                                .onAppear {
                                    if idx == 0 {
                                        Task { await vm.loadOlder() }
                                    }
                                }
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

    @ViewBuilder
    private var typingPill: some View {
        if !vm.typingFromMembers.isEmpty {
            HStack {
                Text(typingPillText)
                    .font(.sacredMicro)
                    .italic()
                    .foregroundColor(.sacredMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.sacredBgCard))
                Spacer()
            }
            .padding(.horizontal, SacredSpacing.m)
            .padding(.bottom, 4)
            .transition(.opacity)
        }
    }

    /// 1:1 today is always one name. The branchpoints for multi-typer
    /// strings exist so groups will format correctly with no model
    /// changes — only this string formatter changes.
    private var typingPillText: String {
        let count = vm.typingFromMembers.count
        if count == 0 { return "" }
        // For 1:1 the only typer is the friend.
        if count == 1 { return "\(friend.displayName) is typing…" }
        if count == 2 { return "\(friend.displayName) and 1 other are typing…" }
        return "\(friend.displayName) and \(count - 1) others are typing…"
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if vm.editingMessageId != nil {
                editBanner
            }
            if let reply = vm.replyTarget {
                replyBanner(reply)
            }

            HStack(alignment: .bottom, spacing: 8) {
                if vm.editingMessageId == nil {
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
                }

                TextField(vm.editingMessageId == nil ? "Message" : "Edit message", text: $draft, axis: .vertical)
                    .font(.sacredText)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.sacredBgCard))

                Button {
                    submitDraft()
                } label: {
                    Image(systemName: vm.editingMessageId == nil ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(canSend ? .sacredGold : .sacredMutedLight)
                }
                .disabled(!canSend || vm.sending)
            }
        }
        .padding(.horizontal, SacredSpacing.m)
        .padding(.vertical, SacredSpacing.s)
        .background(Color.sacredBg)
        .overlay(Rectangle().fill(Color.sacredGold.opacity(0.1)).frame(height: 0.5), alignment: .top)
    }

    private var editBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.sacredGold)
            Text("Editing message")
                .font(.sacredMicroBold)
                .foregroundColor(.sacredTextSecondary)
            Spacer()
            Button("Cancel") {
                vm.cancelEdit()
                draft = ""
            }
            .font(.sacredMicroBold)
            .foregroundColor(.sacredGold)
        }
    }

    private func replyBanner(_ message: FriendMessage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.sacredGold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to \(vm.isFromFriend(message) ? friend.displayName : "you")")
                    .font(.sacredMicroBold)
                    .foregroundColor(.sacredTextSecondary)
                Text(replyPreviewText(for: message))
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
                    .lineLimit(1)
            }
            Spacer()
            Button("Cancel") {
                vm.cancelReply()
            }
            .font(.sacredMicroBold)
            .foregroundColor(.sacredGold)
        }
    }

    private func submitDraft() {
        let text = draft
        if vm.editingMessageId != nil {
            vm.editingDraft = text
            draft = ""
            Task { await vm.submitEdit() }
        } else {
            draft = ""
            Task { await vm.sendText(text) }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendPickedImage(_ item: PhotosPickerItem) async {
        defer { photoSelection = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let prepared = Self.prepareImageForUpload(data) else {
            vm.errorMessage = "Could not prepare that image."
            return
        }
        await vm.sendImage(data: prepared, contentType: "image/jpeg")
    }

    private func replyPreviewText(for message: FriendMessage) -> String {
        if message.isDeleted { return "Message deleted" }
        switch message.kind {
        case .text:
            return message.body ?? "Message"
        case .image:
            return "Photo"
        case .voice:
            return "Voice message"
        }
    }

    private static func prepareImageForUpload(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 2048
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let flattened = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return flattened.jpegData(compressionQuality: 0.82)
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

/// Identifiable wrapper for `.fullScreenCover(item:)` driven by a URL.
private struct PreviewedImage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct MessageBubble: View {
    let message: FriendMessage
    let fromFriend: Bool
    let friendDisplayName: String
    let friendAvatarUrl: String?
    let showAvatar: Bool
    let onTapImage: (URL) -> Void

    /// Reserved width for the avatar gutter on the friend's side. Even
    /// on continuation rows (where we hide the avatar), the slot stays
    /// so successive bubbles in a run align vertically with the first.
    private let avatarSize: CGFloat = 28
    private let avatarGap: CGFloat = 6

    var body: some View {
        HStack(alignment: .bottom, spacing: avatarGap) {
            if fromFriend {
                if showAvatar {
                    SacredAvatar(
                        displayName: friendDisplayName,
                        avatarUrl: friendAvatarUrl,
                        size: avatarSize)
                } else {
                    Color.clear.frame(width: avatarSize, height: avatarSize)
                }
            } else {
                Spacer(minLength: 32)
            }

            VStack(alignment: fromFriend ? .leading : .trailing, spacing: 2) {
                if let reply = message.replyPreview {
                    replyPreview(reply)
                }
                content
                metaLine
            }

            if fromFriend { Spacer(minLength: 32) }
        }
    }

    private func replyPreview(_ reply: FriendMessageReplyPreview) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(reply.senderUserId == message.senderUserId ? "Replying to themselves" : "Replying")
                .font(.sacredMicroBold)
                .foregroundColor(.sacredGold)
            Text(replyText(reply))
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 240, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.sacredBgCard.opacity(0.7)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.sacredGold.opacity(0.16), lineWidth: 1)
        )
    }

    private func replyText(_ reply: FriendMessageReplyPreview) -> String {
        if reply.isDeleted { return "Message deleted" }
        switch reply.kind {
        case .text:
            return reply.body ?? "Message"
        case .image:
            return "Photo"
        case .voice:
            return "Voice message"
        }
    }

    @ViewBuilder
    private var content: some View {
        if message.isDeleted {
            // Deleted-for-everyone placeholder. No avatar weight, no
            // media. The body text is replaced with a muted italic line.
            Text("Message deleted")
                .font(.sacredText)
                .italic()
                .foregroundColor(.sacredMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.sacredBgCard.opacity(0.5)))
        } else {
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
                    .contentShape(Rectangle())
                    .onTapGesture { onTapImage(url) }
                }
            case .voice:
                VoicePlayerView(url: message.mediaUrl, durationMs: message.durationMs, fromFriend: fromFriend)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    /// Timestamp + "edited" marker + read-receipt checkmarks. Kept on
    /// one row so a long bubble doesn't get a tall metadata footer.
    private var metaLine: some View {
        HStack(spacing: 4) {
            if message.isEdited && !message.isDeleted {
                Text("edited")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
            }
            Text(timeLabel)
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)

            // Outgoing-only read receipt. Tiny friend avatar appears
            // once they've read the message — same approach iMessage and
            // Instagram use, more personal than a checkmark and reuses
            // the avatar already on the friend's bubbles. While the
            // message is unread, the slot stays empty (no "sent" tick;
            // delivery is implicit if the row appeared at all).
            if !fromFriend && !message.isDeleted && message.readAt != nil {
                SacredAvatar(
                    displayName: friendDisplayName,
                    avatarUrl: friendAvatarUrl,
                    size: 12)
            }
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
