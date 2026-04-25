import Foundation
import SwiftUI

@MainActor
final class FriendChatViewModel: ObservableObject {
    let friendshipId: UUID
    let friendUserId: UUID
    let friendDisplayName: String

    @Published var messages: [FriendMessage] = []
    @Published var loading = false
    @Published var sending = false
    @Published var errorMessage: String?

    private var observer: NSObjectProtocol?
    private var loadedAll = false

    init(friendshipId: UUID, friendUserId: UUID, friendDisplayName: String) {
        self.friendshipId = friendshipId
        self.friendUserId = friendUserId
        self.friendDisplayName = friendDisplayName
        observer = NotificationCenter.default.addObserver(
            forName: .friendMessageReceived,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let received = note.userInfo?["friendshipId"] as? String
            if received == self.friendshipId.uuidString.lowercased()
                || received == self.friendshipId.uuidString {
                Task { await self.refresh() }
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        do {
            let loaded = try await FriendsAPI.listMessages(friendshipId: friendshipId, limit: 50)
            messages = loaded
            errorMessage = nil
            await markUnreadAsRead()
        } catch {
            if !error.isCancellation {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadOlder() async {
        guard !loadedAll, let oldest = messages.first,
              let oldestDate = FriendsDates.parse(oldest.sentAt) else { return }
        do {
            let older = try await FriendsAPI.listMessages(friendshipId: friendshipId, before: oldestDate, limit: 50)
            if older.isEmpty { loadedAll = true; return }
            messages = older + messages
        } catch {
            // silent; the caller can retry
        }
    }

    func sendText(_ body: String) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            let msg = try await FriendsAPI.sendText(friendshipId: friendshipId, body: trimmed)
            messages.append(msg)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendImage(data: Data, contentType: String) async {
        sending = true
        defer { sending = false }
        do {
            let upload = try await FriendsAPI.createImageUpload(friendshipId: friendshipId, contentType: contentType)
            try await FriendsAPI.uploadMedia(uploadUrl: upload.uploadUrl, contentType: contentType, data: data)
            let msg = try await FriendsAPI.commitImage(friendshipId: friendshipId, objectKey: upload.objectKey)
            messages.append(msg)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendVoice(data: Data, contentType: String, durationMs: Int) async {
        sending = true
        defer { sending = false }
        do {
            let upload = try await FriendsAPI.createVoiceUpload(friendshipId: friendshipId, contentType: contentType)
            try await FriendsAPI.uploadMedia(uploadUrl: upload.uploadUrl, contentType: contentType, data: data)
            let msg = try await FriendsAPI.commitVoice(
                friendshipId: friendshipId,
                objectKey: upload.objectKey,
                durationMs: durationMs)
            messages.append(msg)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markUnreadAsRead() async {
        for m in messages where m.readAt == nil && m.senderUserId == friendUserId {
            try? await FriendsAPI.markRead(friendshipId: friendshipId, messageId: m.id)
        }
    }

    func isFromFriend(_ message: FriendMessage) -> Bool {
        message.senderUserId == friendUserId
    }
}
