import SwiftUI
import PhotosUI
import UIKit

/// 1:1 chat with a friend — text, image, and voice messages.
struct FriendChatView: View {
    /// Constructor-time snapshot. Live updates flow through the
    /// `circleVM.connections` lookup below so nickname / display name
    /// changes reflect without re-pushing the view.
    let connection: Connection
    @ObservedObject var circleVM: CircleViewModel
    @StateObject private var vm: FriendChatViewModel
    @State private var draft: String = ""
    @State private var photoSelection: PhotosPickerItem?
    @State private var showRecorder = false
    @State private var reactionPickerTarget: FriendMessage?
    @State private var imagePreview: PreviewedImage?
    @State private var didInitialScroll = false
    @State private var jumpToMessageId: UUID?
    @State private var highlightedMessageId: UUID?
    @State private var showProfile = false
    @FocusState private var composerFocused: Bool
    @EnvironmentObject var profile: ProfileService
    @Environment(\.dismiss) private var dismiss

    init(connection: Connection, circleVM: CircleViewModel) {
        precondition(connection.messageable, "FriendChatView requires a messageable connection")
        self.connection = connection
        self.circleVM = circleVM
        _vm = StateObject(wrappedValue: FriendChatViewModel(
            friendshipId: connection.friendshipId!,
            friendUserId: connection.person.userId!,
            friendDisplayName: connection.person.displayName))
    }

    /// Live connection record from the circle — picks up annotation
    /// updates (nickname, etc.) without re-pushing the view. Falls back
    /// to the constructor-time copy if the row briefly drops out of
    /// `connections` during a refresh.
    private var currentConnection: Connection {
        circleVM.connections.first(where: { $0.id == connection.id }) ?? connection
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList

            typingPill

            composer
                .background(Color.sacredBg)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            // Tappable header — pushes the friend's profile (nickname,
            // private notes, end friendship). Replaces the previous
            // `navigationTitle` + trailing `...` menu.
            ToolbarItem(placement: .principal) {
                Button { showProfile = true } label: {
                    Text(currentConnection.displayLabel)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundColor(.sacredText)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(isPresented: $showProfile) {
            ConnectionDetailView(connectionId: connection.id, vm: circleVM)
        }
        .sheet(item: $reactionPickerTarget) { target in
            ReactionPickerSheet(
                canEdit: vm.canEdit(target),
                canDelete: vm.canDelete(target),
                onPick: { emoji in
                    reactionPickerTarget = nil
                    if let me = profile.currentUserId {
                        Task { await vm.toggleReaction(emoji, on: target.id, currentUserId: me) }
                    }
                },
                onEdit: {
                    reactionPickerTarget = nil
                    vm.beginEdit(target)
                    draft = target.body ?? ""
                },
                onDelete: {
                    reactionPickerTarget = nil
                    Task { await vm.deleteMessage(target) }
                })
                .presentationDetents([.height(vm.canEdit(target) || vm.canDelete(target) ? 200 : 140)])
                .presentationDragIndicator(.visible)
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
            ChatImageViewer(url: item.url, messageId: item.messageId)
        }
    }

    /// Stable sentinel id pinned to the very end of the LazyVStack —
    /// scrolling to this rather than the last message's id forces the
    /// stack to lay out *through* the actual bottom row, which is the
    /// only way `proxy.scrollTo(_, anchor: .bottom)` reliably lands on
    /// the latest message in a lazy stack (otherwise it parks near the
    /// last-materialized row and leaves the newest bubble clipped).
    private static let bottomAnchorId = "chat-bottom-anchor"

    /// Snap the scroll view to the bottom of the thread on first appear.
    /// Three passes catch the common reflow points: SwiftUI's first
    /// commit, the cache-hydrate / API-merge moment, and any late image
    /// or voice bubble whose async size resolves last. One-shot via
    /// `didInitialScroll` so subsequent re-renders don't yank the user
    /// back down when they've scrolled up to read history.
    private func initialScrollIfNeeded(proxy: ScrollViewProxy) async {
        guard !didInitialScroll else { return }
        guard !vm.messages.isEmpty || !vm.outbox.isEmpty else { return }

        try? await Task.sleep(nanoseconds: 80_000_000)
        proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
        try? await Task.sleep(nanoseconds: 160_000_000)
        proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
        try? await Task.sleep(nanoseconds: 250_000_000)
        proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
        didInitialScroll = true
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
                if vm.loading && vm.messages.isEmpty && vm.outbox.isEmpty {
                    ProgressView().padding(.top, SacredSpacing.xl)
                } else if vm.messages.isEmpty && vm.outbox.isEmpty {
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
                            SwipeToReplyRow(enabled: !msg.isDeleted) {
                                vm.beginReply(msg)
                            } content: {
                                MessageBubble(
                                    message: msg,
                                    fromFriend: vm.isFromFriend(msg),
                                    friendDisplayName: currentConnection.displayLabel,
                                    friendAvatarUrl: currentConnection.person.avatarUrl,
                                    showAvatar: shouldShowAvatar(at: idx),
                                    currentUserId: profile.currentUserId,
                                    isHighlighted: highlightedMessageId == msg.id,
                                    onTapImage: { url in imagePreview = PreviewedImage(url: url, messageId: msg.id) },
                                    onTapReaction: { emoji in
                                        if let me = profile.currentUserId {
                                            Task { await vm.toggleReaction(emoji, on: msg.id, currentUserId: me) }
                                        }
                                    },
                                    onTapReplyPreview: { parentId in jumpToMessage(parentId) },
                                    onTapAvatar: { showProfile = true })
                            }
                            .id(msg.id)
                            .onLongPressGesture {
                                if !msg.isDeleted {
                                    reactionPickerTarget = msg
                                }
                            }
                            .onAppear {
                                if idx == 0 {
                                    Task { await vm.loadOlder() }
                                }
                            }
                        }

                        // Pending sends — text-only for v1 — render
                        // after the real thread so they always appear
                        // at the bottom while in flight.
                        ForEach(vm.outbox) { pending in
                            PendingBubble(
                                pending: pending,
                                onRetry: { Task { await vm.retryPending(pending.id) } },
                                onDelete: { vm.deletePending(pending.id) })
                        }

                        // Sentinel: gives `scrollTo(_, anchor: .bottom)`
                        // a stable row past the last bubble so the lazy
                        // stack always materializes through the real
                        // bottom of the thread.
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorId)
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
            .scrollDismissesKeyboard(.interactively)
            // Initial scroll-to-bottom. `defaultScrollAnchor(.bottom)`
            // doesn't reliably re-anchor after LazyVStack reflows
            // (especially with image bubbles resizing after async
            // load), so do an explicit jump on first appear and also
            // any time messages get populated for the first time.
            // No animation here so the chat opens AT the bottom rather
            // than animating from the top.
            .task {
                await initialScrollIfNeeded(proxy: proxy)
            }
            .onChange(of: vm.messages.count) { _, _ in
                if !didInitialScroll {
                    Task { await initialScrollIfNeeded(proxy: proxy) }
                }
            }
            .onChange(of: vm.messages.last?.id) { _, newId in
                guard newId != nil else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                }
            }
            .onChange(of: vm.outbox.last?.id) { _, newId in
                // Keep the pending bubble in view while in flight so the
                // user can see the "sending" → "failed" transition.
                guard newId != nil else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                }
            }
            .onChange(of: jumpToMessageId) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(target, anchor: .center)
                }
                jumpToMessageId = nil
            }
            .onChange(of: composerFocused) { _, focused in
                // When the keyboard slides up, the ScrollView's content
                // doesn't shift on its own, so the latest message ends up
                // tucked behind the keyboard. Re-anchor to the bottom on
                // every focus event — two passes because the first fires
                // before UIKit has finalized the keyboard frame.
                guard focused else { return }
                guard !vm.messages.isEmpty || !vm.outbox.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                }
                Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    /// Scroll to and briefly highlight the message with the given id —
    /// the destination of a tapped reply preview. Highlight clears
    /// itself after a beat so the user sees the landing without a
    /// permanent visual marker.
    private func jumpToMessage(_ id: UUID) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        jumpToMessageId = id
        withAnimation(.easeInOut(duration: 0.2)) {
            highlightedMessageId = id
        }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.4)) {
                    if highlightedMessageId == id { highlightedMessageId = nil }
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
        if count == 1 { return "\(currentConnection.displayLabel) is typing…" }
        if count == 2 { return "\(currentConnection.displayLabel) and 1 other are typing…" }
        return "\(currentConnection.displayLabel) and \(count - 1) others are typing…"
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
                    .focused($composerFocused)

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
                Text("Replying to \(vm.isFromFriend(message) ? currentConnection.displayLabel : "you")")
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

}

/// Identifiable wrapper for `.fullScreenCover(item:)` driven by a URL.
private struct PreviewedImage: Identifiable {
    let url: URL
    let messageId: UUID?
    var id: String { url.absoluteString }
}

/// Outgoing-bubble shape for an outbox entry that hasn't reached the
/// server yet. Visually mirrors a real outgoing bubble (right-aligned,
/// gold gradient) but with a status badge instead of a timestamp:
///   - `Sending…` while in flight
///   - `Failed — tap to retry` when the last attempt errored
/// Long-press exposes Retry / Delete so the user can drop a stuck send.
private struct PendingBubble: View {
    let pending: PendingMessage
    let onRetry: () -> Void
    let onDelete: () -> Void

    @State private var showActions = false

    var body: some View {
        HStack {
            Spacer(minLength: 32)

            VStack(alignment: .trailing, spacing: 2) {
                Text(pending.body)
                    .font(.sacredText)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(LinearGradient.sacredGoldShinyVertical)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .opacity(pending.lastError == nil ? 0.7 : 1.0)

                statusLine
            }

            // Reserve the same right-side gutter as outgoing bubbles
            // so the pending bubble visually aligns with the real ones.
            Spacer().frame(width: 28)
        }
        .id(pending.id)
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap on a failed bubble retries directly (matches the
            // "tap to retry" badge copy). Successful in-flight bubbles
            // ignore the tap — wait or long-press to delete.
            if pending.lastError != nil { onRetry() }
        }
        .onLongPressGesture { showActions = true }
        .confirmationDialog("Pending message", isPresented: $showActions) {
            if pending.lastError != nil {
                Button("Retry") { onRetry() }
            }
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let err = pending.lastError {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.sacredRed)
                Text("Failed — tap to retry")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredRed)
            }
            .accessibilityLabel("Send failed: \(err)")
        } else {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.sacredMuted)
                Text("Sending…")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
            }
        }
    }
}

private struct MessageBubble: View {
    let message: FriendMessage
    let fromFriend: Bool
    let friendDisplayName: String
    let friendAvatarUrl: String?
    let showAvatar: Bool
    let currentUserId: UUID?
    let isHighlighted: Bool
    let onTapImage: (URL) -> Void
    let onTapReaction: (String) -> Void
    let onTapReplyPreview: (UUID) -> Void
    let onTapAvatar: () -> Void

    /// Reserved width for the avatar gutter on the friend's side. Even
    /// on continuation rows (where we hide the avatar), the slot stays
    /// so successive bubbles in a run align vertically with the first.
    private let avatarSize: CGFloat = 28
    private let avatarGap: CGFloat = 6

    private var hasReactions: Bool {
        (message.reactions ?? []).contains { !$0.byUserIds.isEmpty }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: avatarGap) {
            if fromFriend {
                if showAvatar {
                    Button(action: onTapAvatar) {
                        SacredAvatar(
                            displayName: friendDisplayName,
                            avatarUrl: friendAvatarUrl,
                            size: avatarSize)
                    }
                    .buttonStyle(.plain)
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
                    .overlay(alignment: .bottomTrailing) {
                        reactionRow
                            .offset(x: 14, y: 10)
                    }
                    .padding(.bottom, hasReactions ? 12 : 0)
                    .padding(.trailing, hasReactions ? 4 : 0)
                metaLine
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.sacredGold.opacity(isHighlighted ? 0.16 : 0))
            )

            if fromFriend { Spacer(minLength: 32) }
        }
    }

    private func replyPreview(_ reply: FriendMessageReplyPreview) -> some View {
        Button { onTapReplyPreview(reply.id) } label: {
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
        .buttonStyle(.plain)
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
                    CachedAsyncImage(messageId: message.id, remoteUrl: url)
                        .frame(maxWidth: 240, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                        .onTapGesture { onTapImage(url) }
                }
            case .voice:
                VoicePlayerView(
                    messageId: message.id,
                    url: message.mediaUrl,
                    durationMs: message.durationMs,
                    fromFriend: fromFriend)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    /// Timestamp + "edited" marker + read-receipt checkmarks. Kept on
    /// one row so a long bubble doesn't get a tall metadata footer.
    /// Inline reaction pills below the bubble. Tap your own pill to
    /// remove it; tap a non-mine pill to react with that emoji yourself
    /// (the view model handles upsert vs replace under the hood).
    @ViewBuilder
    private var reactionRow: some View {
        let rows = (message.reactions ?? []).filter { !$0.byUserIds.isEmpty }
        if !rows.isEmpty {
            HStack(spacing: 4) {
                ForEach(rows) { row in
                    let mine = row.isMine(currentUserId: currentUserId)
                    Button { onTapReaction(row.emoji) } label: {
                        HStack(spacing: 3) {
                            Text(row.emoji).font(.system(size: 11))
                            if row.count > 1 {
                                Text("\(row.count)")
                                    .font(.sacredMicroBold)
                                    .foregroundColor(mine ? .sacredGoldDark : .sacredMuted)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(mine
                                ? Color.sacredGold.opacity(0.18)
                                : Color.sacredBgCard))
                        .overlay(
                            Capsule().stroke(mine
                                ? Color.sacredGold.opacity(0.5)
                                : Color.sacredMuted.opacity(0.15),
                                lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
    }

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

/// Quick-emoji picker shown by long-press on a message. Six fixed
/// emojis cover the common acknowledgement set — fancy full-emoji
/// pickers can come later if anyone asks. For the user's own messages
/// the sheet also surfaces Edit / Delete below the emoji row.
private struct ReactionPickerSheet: View {
    let canEdit: Bool
    let canDelete: Bool
    let onPick: (String) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private let emojis = ["❤️", "👍", "😂", "🙏", "😢", "🔥"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ForEach(emojis, id: \.self) { emoji in
                    Button { onPick(emoji) } label: {
                        Text(emoji)
                            .font(.system(size: 32))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.sacredBgCard))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, SacredSpacing.m)

            if canEdit || canDelete {
                Divider()
                    .background(Color.sacredGold.opacity(0.15))
                    .padding(.top, 18)
                    .padding(.horizontal, SacredSpacing.m)

                HStack(spacing: 24) {
                    if canEdit {
                        Button(action: onEdit) {
                            Label("Edit", systemImage: "pencil")
                                .font(.sacredText)
                                .foregroundColor(.sacredGold)
                        }
                        .buttonStyle(.plain)
                    }
                    if canDelete {
                        Button(action: onDelete) {
                            Label("Delete", systemImage: "trash")
                                .font(.sacredText)
                                .foregroundColor(.sacredRed)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 14)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Color.sacredBg.ignoresSafeArea())
    }
}

/// Drag a row to the right to start a reply. The icon on the leading
/// edge fades and scales in as the drag progresses; crossing the
/// threshold fires a haptic and triggers `onReply` on release. Only
/// horizontal-dominant drags engage so vertical scrolling is preserved.
private struct SwipeToReplyRow<Content: View>: View {
    let enabled: Bool
    let onReply: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var dragX: CGFloat = 0
    @State private var didFireHaptic = false

    private let threshold: CGFloat = 60
    private let maxDrag: CGFloat = 90

    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "arrow.turn.up.left")
                .font(.system(size: 18, weight: .light))
                .foregroundColor(.sacredGold)
                .opacity(min(Double(dragX / threshold), 1.0))
                .scaleEffect(min(max(dragX / threshold, 0.4), 1.0))
                .padding(.leading, 12)

            content()
                .offset(x: min(dragX, maxDrag))
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard enabled else { return }
                            // Horizontal-dominant only — let the ScrollView keep vertical drags.
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let x = max(0, value.translation.width)
                            dragX = x
                            if !didFireHaptic && x >= threshold {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                didFireHaptic = true
                            }
                        }
                        .onEnded { _ in
                            if enabled && dragX >= threshold {
                                onReply()
                            }
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                dragX = 0
                            }
                            didFireHaptic = false
                        }
                )
        }
    }
}
