import SwiftUI
import AVKit

/// Apple-Photos-style fullscreen media viewer used everywhere a user
/// opens a photo or video in this app — owner-private keepsakes,
/// shared chat media, and chat-bubble taps. The chrome (top bar with
/// timestamp pill, bottom action row, swipe-between-pages, pinch-zoom,
/// double-tap-to-zoom) is identical across surfaces; the call site
/// just opts into the actions that apply to its kind.
///
/// Pass `nil` for any callback whose action shouldn't be exposed —
/// the corresponding affordance hides automatically. Share is always
/// rendered because every item has a presigned URL we can hand to
/// `UIActivityViewController`.
struct MediaViewer: View {
    let items: [MediaViewerItem]
    /// Optional resolver — called per-page on appear to substitute a
    /// local file URL for the remote one when a cached copy exists.
    /// Returning nil falls back to the item's `remoteUrl`.
    let localUrlResolver: ((MediaViewerItem) async -> URL?)?
    let isOffline: ((MediaViewerItem) -> Bool)?
    let onCaption: ((MediaViewerItem) -> Void)?
    let onDelete: ((MediaViewerItem) -> Void)?
    let onSaveOffline: ((MediaViewerItem) -> Void)?
    let onRemoveOffline: ((MediaViewerItem) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var currentId: UUID
    @State private var showShareSheet = false
    @State private var sharedURL: URL?

    init(
        items: [MediaViewerItem],
        initialId: UUID,
        localUrlResolver: ((MediaViewerItem) async -> URL?)? = nil,
        isOffline: ((MediaViewerItem) -> Bool)? = nil,
        onCaption: ((MediaViewerItem) -> Void)? = nil,
        onDelete: ((MediaViewerItem) -> Void)? = nil,
        onSaveOffline: ((MediaViewerItem) -> Void)? = nil,
        onRemoveOffline: ((MediaViewerItem) -> Void)? = nil
    ) {
        self.items = items
        self.localUrlResolver = localUrlResolver
        self.isOffline = isOffline
        self.onCaption = onCaption
        self.onDelete = onDelete
        self.onSaveOffline = onSaveOffline
        self.onRemoveOffline = onRemoveOffline
        _currentId = State(initialValue: initialId)
    }

    /// Active page. Falls back to the first item if currentId can't be
    /// matched (shouldn't happen — the parent dismisses the viewer
    /// before mutating items — but the fallback keeps the chrome alive).
    private var current: MediaViewerItem {
        items.first(where: { $0.id == currentId }) ?? items[0]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // .page TabView gives the Apple-Photos horizontal swipe
            // between items. Per-page zoom/pan state lives on
            // `MediaViewerPage` so swiping reliably resets it (state
            // is tied to the page identity).
            TabView(selection: $currentId) {
                ForEach(items) { item in
                    MediaViewerPage(item: item, localUrlResolver: localUrlResolver)
                        .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        // Register the chrome as safe-area insets so the TabView's photo
        // is always bounded *inside* the top/bottom bars regardless of
        // the photo's aspect ratio. Without this, screenshots whose
        // aspect matches the device fill the screen and the chrome ends
        // up overlapping photo content (and vice versa). Apple Photos'
        // floating chrome relies on the photo letterboxing — that's not
        // a guarantee for arbitrary chat-attached screenshots.
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .statusBar(hidden: true)
        .sheet(isPresented: $showShareSheet) {
            if let url = sharedURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            chromeButton(systemName: "chevron.backward") { dismiss() }
            Spacer()
            timestampPill
            Spacer()
            if hasMenu {
                chromeMenu
            } else {
                // Reserve the trailing slot so the timestamp stays
                // visually centered across surfaces with and without
                // a menu.
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, SacredSpacing.m)
        .padding(.top, SacredSpacing.m)
    }

    private var hasMenu: Bool {
        onCaption != nil
            || onDelete != nil
            || onSaveOffline != nil
            || onRemoveOffline != nil
    }

    private func chromeButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
    }

    private var timestampPill: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                if isOffline?(current) == true {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.sacredGoldShine)
                }
                Text(timestampDay(for: current))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(timestampTime(for: current))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }

    private var chromeMenu: some View {
        Menu {
            if let onCaption {
                Button {
                    onCaption(current)
                } label: {
                    Label(
                        (current.caption?.isEmpty == false) ? "Edit caption" : "Add caption",
                        systemImage: "text.bubble")
                }
            }
            if let onSaveOffline, let onRemoveOffline {
                if isOffline?(current) == true {
                    Button {
                        onRemoveOffline(current)
                    } label: {
                        Label("Remove from offline", systemImage: "icloud.slash")
                    }
                } else {
                    Button {
                        onSaveOffline(current)
                    } label: {
                        Label("Save for offline", systemImage: "arrow.down.circle")
                    }
                }
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete(current)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
    }

    /// Bottom action bar. Caption (if any) sits above the action row so
    /// it stays visible while the actions are tappable. Caption and
    /// delete buttons hide when their callbacks are absent (e.g. chat
    /// images don't have captions; viewers without delete-permission
    /// don't render the trash).
    private var bottomBar: some View {
        VStack(spacing: SacredSpacing.s) {
            if let caption = current.caption, !caption.isEmpty {
                Text(caption)
                    .font(.sacredText)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SacredSpacing.l)
                    .padding(.vertical, SacredSpacing.s)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .padding(.horizontal, SacredSpacing.l)
            }
            HStack {
                actionButton(systemName: "square.and.arrow.up") {
                    Task { await prepareShare() }
                }
                if let onCaption {
                    Spacer()
                    actionButton(systemName: "text.bubble") { onCaption(current) }
                }
                if let onDelete {
                    Spacer()
                    actionButton(systemName: "trash", tint: .sacredRed) { onDelete(current) }
                }
                if onCaption == nil && onDelete == nil {
                    // Push the share button to the leading edge so the
                    // bottom bar stays visually balanced when only
                    // share is available.
                    Spacer()
                }
            }
            .padding(.horizontal, 48)
            .padding(.bottom, SacredSpacing.l)
        }
    }

    private func actionButton(
        systemName: String,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }

    /// Resolves the shareable URL right before presenting the share
    /// sheet — prefers a cached local file (so AirDrop / Save-to-Photos
    /// works without network) and falls back to the presigned remote.
    private func prepareShare() async {
        if let resolver = localUrlResolver, let local = await resolver(current) {
            sharedURL = local
        } else {
            sharedURL = URL(string: current.remoteUrl)
        }
        showShareSheet = true
    }

    private func timestampDay(for item: MediaViewerItem) -> String {
        if Calendar.current.isDateInToday(item.createdAt) { return "Today" }
        if Calendar.current.isDateInYesterday(item.createdAt) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: item.createdAt)
    }

    private func timestampTime(for item: MediaViewerItem) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: item.createdAt)
    }
}

/// One swipeable page in the `MediaViewer` carousel. Owns its own
/// zoom/pan state so swiping to a new page resets back to fit-to-screen.
/// The pan gesture is only attached when zoomed in — otherwise it would
/// swallow the horizontal drag the parent TabView needs to flip pages.
struct MediaViewerPage: View {
    let item: MediaViewerItem
    let localUrlResolver: ((MediaViewerItem) async -> URL?)?

    @State private var resolvedURL: URL?
    @State private var resolving = true
    @State private var imageZoom: CGFloat = 1.0
    @State private var imageZoomBase: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var imageOffsetBase: CGSize = .zero

    var body: some View {
        Group {
            if resolving {
                ProgressView().tint(.white)
            } else if let url = resolvedURL {
                if item.contentType.hasPrefix("video/") {
                    // Lift the AVPlayer out so SwiftUI rebuilds (e.g.
                    // dismissal animation) don't restart playback. Stays
                    // inside the parent's safe area so the chrome bars
                    // don't overlap the video frame (matches photos).
                    MediaViewerVideoHost(url: url)
                } else {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            zoomable(image)
                        case .failure:
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 36))
                                .foregroundColor(.white.opacity(0.6))
                        default:
                            ProgressView().tint(.white)
                        }
                    }
                }
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .task(id: item.id) {
            await resolve()
        }
    }

    private func resolve() async {
        resolving = true
        defer { resolving = false }
        if let resolver = localUrlResolver, let local = await resolver(item) {
            resolvedURL = local
            return
        }
        resolvedURL = URL(string: item.remoteUrl)
    }

    @ViewBuilder
    private func zoomable(_ image: Image) -> some View {
        let base = image
            .resizable()
            .scaledToFit()
            .scaleEffect(imageZoom)
            .offset(imageOffset)
            .gesture(magnificationGesture)
            .onTapGesture(count: 2) { handleDoubleTap() }

        if imageZoom > 1.0 {
            base.simultaneousGesture(panGesture)
        } else {
            base
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                imageZoom = max(1.0, min(4.0, imageZoomBase * value))
            }
            .onEnded { _ in
                imageZoomBase = imageZoom
                if imageZoom <= 1.0 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        imageOffset = .zero
                        imageOffsetBase = .zero
                    }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                imageOffset = CGSize(
                    width: imageOffsetBase.width + value.translation.width,
                    height: imageOffsetBase.height + value.translation.height)
            }
            .onEnded { _ in
                imageOffsetBase = imageOffset
            }
    }

    private func handleDoubleTap() {
        withAnimation(.easeInOut(duration: 0.25)) {
            if imageZoom > 1.0 {
                imageZoom = 1.0
                imageZoomBase = 1.0
                imageOffset = .zero
                imageOffsetBase = .zero
            } else {
                imageZoom = 2.5
                imageZoomBase = 2.5
            }
        }
    }
}

private struct MediaViewerVideoHost: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                if player == nil { player = AVPlayer(url: url) }
                player?.play()
            }
            .onDisappear {
                player?.pause()
            }
    }
}

/// Identifies a single page in the viewer. `id` doubles as the cache
/// key for resolvers (`AttachmentCache` for keepsakes, `ChatMediaCache`
/// for chat) so a closure-based lookup stays portable across surfaces.
struct MediaViewerItem: Identifiable, Equatable {
    let id: UUID
    let contentType: String
    let remoteUrl: String
    let caption: String?
    let createdAt: Date
}
