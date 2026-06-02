import SwiftUI
import AVKit
import UIKit

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
            // Buttons sit as a centered cluster regardless of how many
            // are present — even spacing between them, centered as a
            // group rather than spread to the edges.
            HStack(spacing: SacredSpacing.xl) {
                actionButton(systemName: "square.and.arrow.up") {
                    Task { await prepareShare() }
                }
                if let onCaption {
                    actionButton(systemName: "text.bubble") { onCaption(current) }
                }
                if let onDelete {
                    actionButton(systemName: "trash", tint: .sacredRed) { onDelete(current) }
                }
            }
            .frame(maxWidth: .infinity)
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

/// One swipeable page in the `MediaViewer` carousel.
///
/// Photos use a `UIScrollView`-backed zoom view (`ZoomableImage`) so the
/// pinch, pan, momentum, bounds rubber-banding, and double-tap-to-point
/// all feel like the native Photos viewer — the hand-rolled SwiftUI
/// `MagnificationGesture` version fought the parent `.page` TabView and
/// snapped between zoom levels instead of scaling continuously.
struct MediaViewerPage: View {
    let item: MediaViewerItem
    let localUrlResolver: ((MediaViewerItem) async -> URL?)?

    private enum Phase {
        case loading
        case image(UIImage)
        case video(URL)
        case failed
    }

    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView().tint(.white)
            case .image(let img):
                ZoomableImage(image: img)
            case .video(let url):
                // Lift the AVPlayer out so SwiftUI rebuilds (e.g. the
                // dismissal animation) don't restart playback.
                MediaViewerVideoHost(url: url)
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .task(id: item.id) {
            await load()
        }
    }

    private func load() async {
        phase = .loading

        var url: URL?
        if let resolver = localUrlResolver, let local = await resolver(item) {
            url = local
        } else {
            url = URL(string: item.remoteUrl)
        }
        guard let url else { phase = .failed; return }

        if item.contentType.hasPrefix("video/") {
            phase = .video(url)
            return
        }

        if let image = await Self.loadImage(url) {
            phase = .image(image)
        } else {
            phase = .failed
        }
    }

    /// Local files load straight off disk; remote (presigned) URLs go
    /// through the shared image cache, which strips the rotating query
    /// params and keeps the full-resolution bytes on disk.
    private static func loadImage(_ url: URL) async -> UIImage? {
        if url.isFileURL {
            return UIImage(contentsOfFile: url.path)
        }
        return await AvatarImageCache.shared.image(for: url)
    }
}

// MARK: - Native zoom (UIScrollView-backed)

/// Wraps a `UIScrollView` + `UIImageView` so pinch-zoom anchors at the
/// fingers, panning has momentum and bounds rubber-banding, and
/// double-tap zooms toward the tapped point — the native Photos feel
/// that pure-SwiftUI gestures can't match.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomImageScrollView {
        let view = ZoomImageScrollView()
        view.setImage(image)
        return view
    }

    func updateUIView(_ uiView: ZoomImageScrollView, context: Context) {
        uiView.setImage(image)
    }
}

/// Self-contained zoomable image scroll view. Starts with scrolling
/// disabled so horizontal swipes fall through to the parent `.page`
/// TabView; once zoomed in, scrolling turns on so the user can pan the
/// enlarged image. Pinch-to-zoom is always live (it rides a separate
/// gesture recognizer), which is what lets the pager and the zoom
/// coexist without fighting.
final class ZoomImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var lastBoundsSize: CGSize = .zero

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1.0
        maximumZoomScale = 5.0
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        decelerationRate = .fast
        backgroundColor = .clear
        contentInsetAdjustmentBehavior = .never
        // Off at fit-scale so the parent pager owns horizontal swipes;
        // flipped on once the user zooms in (see didEndZooming).
        isScrollEnabled = false

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: UIImage) {
        // Identity check so SwiftUI re-renders don't reset the zoom mid-
        // gesture; only a genuinely new image re-lays-out.
        guard imageView.image !== image else { return }
        imageView.image = image
        setZoomScale(minimumZoomScale, animated: false)
        isScrollEnabled = false
        lastBoundsSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            zoomScale = minimumZoomScale
            imageView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
        centerImage()
    }

    /// Keep the image centered while it's smaller than the viewport
    /// (at fit-scale, and on every zoom step) via symmetric content inset.
    private func centerImage() {
        let viewport = bounds.size
        let content = imageView.frame.size
        let insetX = max(0, (viewport.width - content.width) / 2)
        let insetY = max(0, (viewport.height - content.height) / 2)
        contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // Pan only matters once we're zoomed past fit; otherwise hand
        // horizontal drags back to the pager.
        isScrollEnabled = scale > minimumZoomScale
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let targetScale = min(maximumZoomScale, 2.5)
            let width = bounds.width / targetScale
            let height = bounds.height / targetScale
            zoom(to: CGRect(x: point.x - width / 2,
                            y: point.y - height / 2,
                            width: width,
                            height: height),
                 animated: true)
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
