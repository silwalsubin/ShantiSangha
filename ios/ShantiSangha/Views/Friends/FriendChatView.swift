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
    /// The id of the row currently aligned with the scroll view's bottom
    /// edge. Bound to `.scrollPosition(id:anchor:)` so iOS keeps that row
    /// pinned at `.bottom` across every layout change — image bubbles
    /// resizing, lazy-stack materialization, message arrivals, keyboard
    /// in/out. Starts as nil and gets assigned in `.task` once the
    /// LazyVStack's bottom-anchor row actually exists; seeding it at
    /// @State init competes with `defaultScrollAnchor(.bottom)` during
    /// the first render and parks the chat scrolled UP. User-driven
    /// scrolling overwrites it (the binding is bidirectional), so
    /// scrolling up to read history doesn't get yanked back when new
    /// messages arrive.
    @State private var pinnedScrollID: String?
    @State private var jumpToMessageId: UUID?
    @State private var highlightedMessageId: UUID?
    @State private var showProfile = false
    /// The reminder suggestion the user just tapped "Schedule" on. When
    /// non-nil, pushes ReminderEditView pre-filled with the extracted
    /// label + date. After save, we POST /suggestion/accept linking the
    /// new reminder back to the message so the card stops re-appearing.
    @State private var suggestionScheduleTarget: SuggestionScheduleTarget?
    /// Mirrors the composer's internal `@FocusState`. The composer pings
    /// us on focus change so we can scroll the latest message above the
    /// keyboard rise.
    @State private var composerFocused: Bool = false
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
        // Composer + typing pill are declared as a bottom safe-area
        // inset of the ScrollView. That tells SwiftUI "this is the
        // bottom of the scroll surface" — when the keyboard opens, the
        // platform shrinks the scroll viewport's bottom inset to make
        // room and the bottom-anchored content lifts automatically.
        // Stacking them in a VStack instead (the previous layout)
        // hides the keyboard-frame change from the ScrollView, which
        // is why the latest message kept ending up tucked behind the
        // keyboard.
        messageList
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                typingPill
                composer
            }
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
        // TODO: thread recurrence pre-fill through ReminderEditTarget.
        // For V1 the editor opens with its default recurrence (yearly);
        // users can flip it before saving when the LLM extracted "none".
        .navigationDestination(item: $suggestionScheduleTarget) { target in
            ReminderEditView(
                target: .new(initialLabel: target.label,
                             initialDate: SuggestionScheduleTarget.parse(target.date),
                             connectionId: target.connectionId),
                onSave: { label, dateString, savedRecurrence, collaboratorIds in
                    do {
                        let created = try await ReminderRepository.shared.create(
                            label: label,
                            date: dateString,
                            recurrence: savedRecurrence,
                            connectionId: target.connectionId,
                            collaboratorUserIds: collaboratorIds)
                        await vm.acceptSuggestion(
                            messageId: target.messageId, reminderId: created.id)
                    } catch {
                        if !error.isCancellation {
                            AppLogger.shared.error("Friends", "Suggestion-driven reminder create failed: \(error)")
                        }
                    }
                },
                onDelete: nil,
                onLivePatch: nil)
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
            // Same MediaViewer as the keepsake + chat-archive surfaces.
            // Single-item array — the chat bubble tap doesn't paginate
            // (matches iMessage), but the chrome and gestures stay
            // identical so users see one viewer everywhere.
            let viewerItemId = item.messageId ?? UUID()
            MediaViewer(
                items: [
                    MediaViewerItem(
                        id: viewerItemId,
                        contentType: "image/jpeg",
                        remoteUrl: item.url.absoluteString,
                        caption: nil,
                        createdAt: messageSentAt(item.messageId) ?? Date())
                ],
                initialId: viewerItemId,
                localUrlResolver: { _ in
                    guard let messageId = item.messageId else { return nil }
                    return await ChatMediaCache.shared.cachedURL(
                        messageId: messageId, remoteUrl: item.url)
                })
        }
    }

    /// Look up the SentAt for a message id so the viewer's timestamp
    /// pill reads "Today / 3:09 PM" — same chrome the keepsake viewer
    /// uses. Falls back to nil for synthetic/unknown ids.
    private func messageSentAt(_ id: UUID?) -> Date? {
        guard let id, let m = vm.messages.first(where: { $0.id == id }) else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: m.sentAt) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: m.sentAt)
    }

    /// Stable sentinel id pinned to the very end of the LazyVStack —
    /// scrollPosition aligns this row at `.bottom`, which is the only
    /// reliable way to land on the latest message in a lazy stack
    /// (otherwise the stack parks near the last-materialized row and
    /// leaves the newest bubble clipped).
    private static let bottomAnchorId = "chat-bottom-anchor"
    private static let groupedMessageSpacing: CGFloat = 2

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

    private func spacingBeforeMessage(at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        let msg = vm.messages[index]
        let prev = vm.messages[index - 1]
        return prev.senderUserId == msg.senderUserId ? Self.groupedMessageSpacing : SacredSpacing.s
    }

    private func spacingBeforePending(at index: Int) -> CGFloat {
        guard index == 0 else { return Self.groupedMessageSpacing }
        guard let last = vm.messages.last else { return 0 }
        return vm.isFromFriend(last) ? SacredSpacing.s : Self.groupedMessageSpacing
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                messageListContent
            }
            .scrollDismissesKeyboard(.interactively)
            // `defaultScrollAnchor(.bottom)` tells the platform to
            // place the initial content at the bottom — the chat opens
            // AT the latest message. This is the platform's official
            // answer for chat layouts, designed to survive lazy-stack
            // reflows and async image loads (the failure mode that
            // broke every previous timing-based fix).
            .defaultScrollAnchor(.bottom)
            // Bidirectional bind: writing `pinnedScrollID =
            // bottomAnchorId` re-aligns the sentinel row to the
            // viewport's bottom, which the system re-applies after
            // every layout change. When the user scrolls up the system
            // writes the visible row's id back into the binding, so
            // subsequent message arrivals don't yank them down.
            .scrollPosition(id: $pinnedScrollID, anchor: .bottom)
            .task {
                // First-render seed. defaultScrollAnchor handles the
                // initial "park at bottom" snap; setting the binding
                // here keeps the bottom anchor "live" so the
                // scrollPosition modifier re-pins after later reflows
                // (message arrivals, image bubble resizes). Done in
                // .task — not at @State init — because pinning to a
                // row id before that row exists in the LazyVStack
                // fights with defaultScrollAnchor and parks the chat
                // scrolled up.
                pinnedScrollID = Self.bottomAnchorId
            }
            .onChange(of: vm.messages.last?.id) { _, newId in
                guard newId != nil else { return }
                // Re-pin only if the user is currently at the bottom —
                // otherwise they're reading history and we leave them
                // alone. `pinnedScrollID` reflects whatever the system
                // last wrote (visible bottom row or our sentinel).
                guard isAtBottom else { return }
                // Drive the scroll imperatively via the proxy. Writing
                // `pinnedScrollID = Self.bottomAnchorId` is a no-op when
                // the binding is already the sentinel (the common case
                // — the seed and every re-pin park it there), so the
                // new bubble would otherwise stay hidden behind the
                // keyboard until the user scrolled. Same workaround as
                // the focus handler below.
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                }
            }
            .onChange(of: vm.outbox.last?.id) { _, newId in
                // The user just sent something — always follow their
                // own sends to the bottom, even if scrolled up.
                guard newId != nil else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                }
            }
            .onChange(of: jumpToMessageId) { _, target in
                // Reply-preview taps still center the parent message,
                // not pin it to the bottom — use the proxy's imperative
                // scrollTo for that case. After the jump the user can
                // tap the new message to scroll back; pinnedScrollID
                // updates passively from the system as they scroll.
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(target.uuidString, anchor: .center)
                }
                jumpToMessageId = nil
            }
            .onChange(of: composerFocused) { _, focused in
                // Keyboard opening shrinks the scroll viewport. With
                // pinnedScrollID seeded to the bottom anchor, the
                // scrollPosition binding will pin the latest bubble
                // automatically — but only when SwiftUI re-evaluates
                // it. Assigning the binding to its current value
                // (Self.bottomAnchorId) is a no-op, so tapping the
                // field before any other interaction has dirtied the
                // binding leaves the latest message hidden. Drive the
                // scroll imperatively via the proxy: it always
                // re-applies, and `withAnimation` syncs it with the
                // keyboard rise. Preserve history reading: if the user
                // is scrolled up, leave them alone.
                guard focused, isAtBottom else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                }
            }
        }
    }

    /// Whether the chat is currently parked at (or pinned to) the
    /// bottom of the thread. We treat "no current pin" as bottom too —
    /// that's the seed state before .task fires.
    private var isAtBottom: Bool {
        pinnedScrollID == nil || pinnedScrollID == Self.bottomAnchorId
    }

    @ViewBuilder
    private var messageListContent: some View {
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
            LazyVStack(spacing: 0) {
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
                            friendAvatarUrl: currentConnection.ownerVisibleAvatarUrl,
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
                            onTapAvatar: { showProfile = true },
                            onScheduleSuggestion: {
                                if let s = msg.suggestion {
                                    suggestionScheduleTarget = SuggestionScheduleTarget(
                                        messageId: msg.id,
                                        label: s.label,
                                        date: s.date,
                                        recurrence: s.recurrence,
                                        connectionId: connection.id)
                                }
                            },
                            onDismissSuggestion: {
                                Task { await vm.dismissSuggestion(messageId: msg.id) }
                            })
                    }
                    .id(msg.id.uuidString)
                    .padding(.top, spacingBeforeMessage(at: idx))
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

                // Pending sends — text-only for v1 — render after the
                // real thread so they always appear at the bottom while
                // in flight.
                ForEach(Array(vm.outbox.enumerated()), id: \.element.id) { idx, pending in
                    PendingBubble(
                        pending: pending,
                        onRetry: { Task { await vm.retryPending(pending.id) } },
                        onDelete: { vm.deletePending(pending.id) })
                    .padding(.top, spacingBeforePending(at: idx))
                }

                // Sentinel row at the very bottom of the lazy stack.
                // `scrollPosition(id:)` aligns this row with the
                // scroll view's bottom edge — keeping it the durable
                // pin point regardless of how the bubbles above resize.
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
        SacredChatComposer(
            text: $draft,
            placeholder: vm.editingMessageId == nil ? "Message" : "Edit message",
            isEditing: vm.editingMessageId != nil,
            canSend: canSend && !vm.sending,
            onSend: submitDraft,
            onFocusChange: { composerFocused = $0 },
            accessories: {
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
            },
            banner: {
                if vm.editingMessageId != nil {
                    editBanner
                } else if let reply = vm.replyTarget {
                    replyBanner(reply)
                }
            })
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
    let onScheduleSuggestion: () -> Void
    let onDismissSuggestion: () -> Void

    private var visibleSuggestion: FriendMessageSuggestion? {
        guard let s = message.suggestion else { return nil }
        if s.dismissed || s.accepted { return nil }
        return s
    }

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
                if let s = visibleSuggestion {
                    SuggestionCard(
                        suggestion: s,
                        alignment: fromFriend ? .leading : .trailing,
                        onSchedule: onScheduleSuggestion,
                        onDismiss: onDismissSuggestion)
                        .padding(.top, 4)
                }
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
                SacredChatBubblePill(side: fromFriend ? .theirs : .mine) {
                    Text(message.body ?? "")
                }
            case .image:
                if let urlStr = message.mediaUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(messageId: message.id, remoteUrl: url)
                        .frame(maxWidth: 240, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                        .onTapGesture { onTapImage(url) }
                }
            case .voice:
                SacredChatBubblePill(side: fromFriend ? .theirs : .mine) {
                    VoicePlayerView(
                        messageId: message.id,
                        url: message.mediaUrl,
                        durationMs: message.durationMs,
                        fromFriend: fromFriend)
                }
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

// MARK: - Inline reminder-suggestion target

/// Identifiable navigation target for the reminder editor opened from a
/// suggestion card. Carries the message id so we can POST /accept once
/// the user saves.
private struct SuggestionScheduleTarget: Identifiable, Hashable {
    let messageId: UUID
    let label: String
    let date: String  // yyyy-MM-dd
    let recurrence: String
    let connectionId: UUID

    var id: String { "\(messageId.uuidString)|\(label)|\(date)" }

    static func parse(_ iso: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: iso)
    }
}

// MARK: - Inline reminder-suggestion card

/// Sacred-gold tinted card that appears below a message bubble when the
/// server detected a reminder-shaped statement in the body. Tapping
/// "Schedule" opens the normal reminder editor pre-filled; tapping
/// "Not now" dismisses just that suggestion.
private struct SuggestionCard: View {
    let suggestion: FriendMessageSuggestion
    let alignment: HorizontalAlignment
    let onSchedule: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if alignment == .trailing { Spacer(minLength: 32) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.sacredMicroBold)
                        .foregroundColor(.sacredGold)
                    Text("REMINDER?")
                        .font(.sacredMicroBold)
                        .tracking(1)
                        .foregroundColor(.sacredGold)
                }
                Text(suggestion.label)
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredText)
                Text(prettyDate(suggestion.date))
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
                HStack(spacing: 8) {
                    Button(action: onSchedule) {
                        Text("Schedule")
                            .font(.sacredSmallSemibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.sacredGold))
                    }
                    .buttonStyle(.plain)
                    Button(action: onDismiss) {
                        Text("Not now")
                            .font(.sacredSmallSemibold)
                            .foregroundColor(.sacredMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().stroke(Color.sacredMuted.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
            .padding(12)
            .frame(maxWidth: 260, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.sacredGold.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.sacredGold.opacity(0.30), lineWidth: 1)
            )
            if alignment == .leading { Spacer(minLength: 32) }
        }
    }

    private func prettyDate(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let d = parser.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: d)
    }
}
