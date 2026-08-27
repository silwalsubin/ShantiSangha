import SwiftUI
import UIKit

/// Presented when a photo is shared into the app from another app's share
/// sheet. The user picks one connection and the photo is sent into that
/// 1:1 chat using the same upload path as the in-chat photo picker, then
/// the sheet confirms and dismisses — returning the user wherever they
/// were. Group/circle broadcast isn't offered because chat is 1:1.
struct ShareToConnectionSheet: View {
    let media: SharedMediaPayload
    /// Called to tear the sheet down (cancel, or after a successful send).
    let onClose: () -> Void

    @State private var connections: [Connection] = []
    @State private var loading = true
    @State private var query = ""
    @State private var selectedId: UUID?
    @State private var sending = false
    @State private var sentToName: String?
    @State private var errorMessage: String?
    @FocusState private var searchFocused: Bool

    /// Sentinel id for the "Assistant" target. Selecting it routes the
    /// photo to the AI assistant instead of a 1:1 connection.
    private let assistantTargetId = UUID()

    private var preview: UIImage? { UIImage(data: media.data) }

    private var canSend: Bool { selectedId != nil && !sending }

    private var messageable: [Connection] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return connections }
        return connections.filter {
            $0.displayLabel.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let sentToName {
                    sentState(sentToName)
                } else {
                    picker
                }
            }
            .background(SacredBackground().ignoresSafeArea())
            .navigationTitle(sentToName == nil ? "Share photo" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if sentToName == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { onClose() }
                            .foregroundColor(.sacredMuted)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Send") { Task { await send() } }
                            .font(.sacredTextSemibold)
                            .foregroundColor(canSend ? .sacredGold : .sacredMuted)
                            .disabled(!canSend)
                    }
                }
            }
        }
        .task { await load() }
        .interactiveDismissDisabled(sending)
    }

    // MARK: - Picker

    private var picker: some View {
        VStack(spacing: 0) {
            thumbnail
            searchField
            Divider().padding(.horizontal, SacredSpacing.m)

            if loading {
                Spacer()
                ProgressView().tint(.sacredGold)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        assistantRow
                        Divider().padding(.leading, 64)

                        ForEach(Array(messageable.enumerated()), id: \.element.id) { idx, conn in
                            row(conn)
                            if idx < messageable.count - 1 {
                                Divider().padding(.leading, 64)
                            }
                        }

                        if connections.isEmpty {
                            Text("Add someone to your circle to share photos with them too.")
                                .font(.sacredMicro)
                                .foregroundColor(.sacredMuted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, SacredSpacing.l)
                                .padding(.top, SacredSpacing.m)
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.sacredMicro)
                    .foregroundColor(.sacredRed)
                    .padding(.vertical, SacredSpacing.s)
            }
        }
        .overlay {
            if sending {
                ZStack {
                    Color.sacredBg.opacity(0.5).ignoresSafeArea()
                    ProgressView().tint(.sacredGold)
                }
            }
        }
    }

    private var thumbnail: some View {
        Group {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: SacredRadius.lux))
                    .overlay(
                        RoundedRectangle(cornerRadius: SacredRadius.lux)
                            .stroke(Color.sacredGold.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .padding(.top, SacredSpacing.m)
        .padding(.bottom, SacredSpacing.s)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
            TextField("Send to…", text: $query)
                .typingHaptics(for: query)
                .focused($searchFocused)
                .font(.sacredSmall)
                .foregroundColor(.sacredText)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.sacredGold.opacity(0.12)))
        .padding(.horizontal, SacredSpacing.m)
        .padding(.bottom, SacredSpacing.s)
    }

    private var assistantRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedId = (selectedId == assistantTargetId) ? nil : assistantTargetId
            searchFocused = false
        } label: {
            HStack(spacing: 12) {
                Image("tab.vajra")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.sacredGold)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.sacredGold.opacity(0.12)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Assistant")
                        .font(.sacredTextSemibold)
                        .foregroundColor(.sacredText)
                    Text("Ask the AI about this photo")
                        .font(.sacredMicro)
                        .foregroundColor(.sacredMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: selectedId == assistantTargetId ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(selectedId == assistantTargetId ? .sacredGold : .sacredMuted.opacity(0.4))
            }
            .padding(.horizontal, SacredSpacing.m)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ conn: Connection) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedId = (selectedId == conn.id) ? nil : conn.id
            searchFocused = false
        } label: {
            HStack(spacing: 12) {
                SacredAvatar(
                    displayName: conn.displayLabel,
                    avatarUrl: conn.ownerVisibleAvatarUrl,
                    size: 40)
                    .frame(width: 44, height: 44)

                Text(conn.displayLabel)
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Image(systemName: selectedId == conn.id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(selectedId == conn.id ? .sacredGold : .sacredMuted.opacity(0.4))
            }
            .padding(.horizontal, SacredSpacing.m)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sentState(_ name: String) -> some View {
        VStack(spacing: SacredSpacing.m) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.sacredGold)
            Text("Sent to \(name)")
                .font(.sacredSubheading)
                .foregroundColor(.sacredText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            connections = try await ConnectionsAPI.list().filter { $0.messageable }
            errorMessage = nil
        } catch {
            if !error.isCancellation {
                errorMessage = "Couldn't load your connections."
            }
        }
    }

    private func send() async {
        // Assistant target: hand the photo to the AI chat (which opens
        // with it staged so the user can add a question), not a connection.
        if selectedId == assistantTargetId {
            DeepLinkRouter.shared.pendingAssistantImage = media
            onClose()
            return
        }

        guard let conn = connections.first(where: { $0.id == selectedId }),
              let friendshipId = conn.friendshipId else { return }
        sending = true
        errorMessage = nil
        do {
            let upload = try await FriendsAPI.createImageUpload(
                friendshipId: friendshipId, contentType: media.contentType)
            try await FriendsAPI.uploadMedia(
                uploadUrl: upload.uploadUrl, contentType: media.contentType, data: media.data)
            _ = try await FriendsAPI.commitImage(
                friendshipId: friendshipId, objectKey: upload.objectKey, replyToMessageId: nil)

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotificationCenter.default.post(name: .friendsUpdated, object: nil)

            sending = false
            withAnimation(.easeIn(duration: 0.25)) { sentToName = conn.displayLabel }
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            onClose()
        } catch {
            sending = false
            if !error.isCancellation {
                errorMessage = "Couldn't send. Try again."
            }
        }
    }
}
