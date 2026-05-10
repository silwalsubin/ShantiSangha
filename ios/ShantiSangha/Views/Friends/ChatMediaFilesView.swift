import SwiftUI

/// Shared chat archive for a friendship — every photo and voice note
/// the two friends have exchanged, visible to BOTH parties (vs. the
/// owner-private `ConnectionAttachmentsView`). Splits into two
/// sections — MEDIA (image messages in a thumbnail grid) and VOICE
/// (audio messages as a list with inline playback). Sections only
/// render when they have items.
///
/// Data flow:
/// - Loads the latest 100 image+voice messages from the dedicated
///   `/messages/media` endpoint (text + soft-deleted are filtered
///   server-side so the page stays small).
/// - Tapping a media tile opens the same `ChatImageViewer` the chat
///   bubbles use — pinch zoom, drag to dismiss, share.
/// - No edits / deletes from this surface; the source of truth is
///   the chat itself, and message-level mutations live there.
struct ChatMediaFilesView: View {
    let friendshipId: UUID
    let connectionDisplayName: String

    @State private var messages: [FriendMessage] = []
    @State private var loading = false
    @State private var didLoadOnce = false
    @State private var errorMessage: String?
    @State private var imagePreview: ChatImagePreviewItem?

    @EnvironmentObject private var profile: ProfileService

    var body: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.l) {
            if didLoadOnce {
                // Sibling of the owner-private flow's lock footnote — the
                // group icon plus "you both can see this" telegraphs that
                // the section is shared, not private.
                SharedFootnote("Both of you can see this — it's everything you've shared in chat.")
                    .padding(.horizontal, SacredSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if !imageMessages.isEmpty {
                mediaSection
            }

            if !voiceMessages.isEmpty {
                voiceSection
                    .padding(.horizontal, SacredSpacing.m)
            }

            if didLoadOnce && !loading && messages.isEmpty {
                emptyState
                    .padding(.horizontal, SacredSpacing.m)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.sacredMicro)
                    .foregroundColor(.sacredRed)
                    .padding(.horizontal, SacredSpacing.m)
            }
        }
        .task(id: friendshipId) {
            await load()
        }
        .fullScreenCover(item: $imagePreview) { item in
            ChatImageViewer(url: item.url, messageId: item.messageId)
        }
    }

    // MARK: - Sections

    private var mediaSection: some View {
        // Edge-to-edge Apple-Photos-style grid: 3 cols, 2pt gutters.
        // Identical chrome to the owner-private grid so the two
        // sections feel like cousins, not strangers.
        LazyVGrid(columns: gridColumns, spacing: 2) {
            ForEach(imageMessages) { msg in
                ChatMediaImageTile(message: msg)
                    .onTapGesture { openImagePreview(msg) }
            }
        }
    }

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("VOICE")
            SacredListCard {
                VStack(spacing: 0) {
                    ForEach(Array(voiceMessages.enumerated()), id: \.element.id) { index, msg in
                        ChatVoiceRow(
                            message: msg,
                            isFromMe: msg.senderUserId == profile.currentUserId,
                            connectionDisplayName: connectionDisplayName)
                        if index < voiceMessages.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: SacredSpacing.s) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28))
                .foregroundColor(.sacredGold.opacity(0.6))
            Text("Nothing shared yet")
                .font(.sacredTextSemibold)
                .foregroundColor(.sacredText)
            Text("Photos and voice notes from your chat will collect here.")
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SacredSpacing.l)
    }

    // MARK: - Derived state

    private var imageMessages: [FriendMessage] {
        messages.filter { $0.kind == .image && $0.deletedAt == nil && $0.mediaUrl != nil }
    }

    private var voiceMessages: [FriendMessage] {
        messages.filter { $0.kind == .voice && $0.deletedAt == nil && $0.mediaUrl != nil }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.sacredSectionLabel)
            .foregroundColor(.sacredLabel)
            .padding(.horizontal, 4)
    }

    // MARK: - Actions

    private func openImagePreview(_ msg: FriendMessage) {
        guard let urlStr = msg.mediaUrl, let url = URL(string: urlStr) else { return }
        imagePreview = ChatImagePreviewItem(url: url, messageId: msg.id)
    }

    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false; didLoadOnce = true }
        do {
            messages = try await FriendsAPI.listChatMedia(friendshipId: friendshipId, limit: 100)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't load shared media. Pull to retry."
        }
    }
}

/// `.fullScreenCover(item:)`-friendly wrapper so the same sheet
/// lifecycle the chat uses applies here.
private struct ChatImagePreviewItem: Identifiable {
    let url: URL
    let messageId: UUID?
    var id: String { url.absoluteString }
}

/// Square thumbnail tile for chat image messages — local-first via
/// `ChatMediaCache` so opening this archive on a previously-viewed
/// chat is instant. Mirrors the keepsake `MediaTile` chrome (true
/// 1:1 frame, .scaledToFill, .clipped) so the two grids visually
/// match without referencing each other's types.
private struct ChatMediaImageTile: View {
    let message: FriendMessage

    @State private var localURL: URL?
    @State private var failed = false

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { thumbnailLayer }
            .clipped()
            .task(id: message.id) {
                await loadThumbnail()
            }
    }

    @ViewBuilder
    private var thumbnailLayer: some View {
        if let localURL, let img = UIImage(contentsOfFile: localURL.path) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if failed {
            Color.sacredBgCard
                .overlay {
                    Image(systemName: "photo")
                        .foregroundColor(.sacredMuted)
                }
        } else {
            Color.sacredBgCard
                .overlay { ProgressView().tint(.sacredGold) }
        }
    }

    private func loadThumbnail() async {
        if localURL != nil { return }
        guard let urlStr = message.mediaUrl, let remote = URL(string: urlStr) else {
            failed = true
            return
        }
        if let url = await ChatMediaCache.shared.cachedURL(
            messageId: message.id,
            remoteUrl: remote) {
            localURL = url
        } else {
            failed = true
        }
    }
}

/// One row in the VOICE list — gold mic glyph + the existing
/// `VoicePlayerView` (same playback used by chat bubbles, so it
/// reuses the on-disk cache for instant replay) + sender + sent-at.
private struct ChatVoiceRow: View {
    let message: FriendMessage
    let isFromMe: Bool
    let connectionDisplayName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.sacredGold)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.sacredGold.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                VoicePlayerView(
                    messageId: message.id,
                    url: message.mediaUrl,
                    durationMs: message.durationMs,
                    fromFriend: !isFromMe)

                Text(secondaryLine)
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var secondaryLine: String {
        let who = isFromMe ? "You" : connectionDisplayName
        return "\(who) · \(formattedSentAt)"
    }

    private var formattedSentAt: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date: Date = {
            if let d = f.date(from: message.sentAt) { return d }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: message.sentAt) ?? Date()
        }()

        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let df = DateFormatter()
            df.dateFormat = "h:mm a"
            return df.string(from: date)
        }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy"
        return df.string(from: date)
    }
}
