import SwiftUI

/// Full-screen wrapper around `ChatMediaFilesView`. Sibling of
/// `ConnectionAttachmentsScreen` — same shape and chrome, but the
/// content is the shared chat archive (visible to both parties)
/// rather than the owner-private keepsakes.
struct ChatMediaFilesScreen: View {
    let friendshipId: UUID
    let connectionDisplayName: String

    var body: some View {
        ScrollView {
            // Edge-to-edge media grid — file/voice rows pad themselves.
            ChatMediaFilesView(
                friendshipId: friendshipId,
                connectionDisplayName: connectionDisplayName)
                .padding(.vertical, SacredSpacing.l)
        }
        .background(SacredBackground().ignoresSafeArea())
        .navigationTitle("Chat Media & Files")
        .navigationBarTitleDisplayMode(.inline)
    }
}
