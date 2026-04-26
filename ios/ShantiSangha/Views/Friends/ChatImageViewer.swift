import SwiftUI

/// Fullscreen photo viewer for chat images. Pinch + drag to zoom, swipe
/// down to dismiss, share button to save to Photos / send / copy via the
/// system share sheet (which surfaces "Save Image" automatically when
/// given a UIImage).
///
/// Downloads the image bytes once on appear (separate from the bubble's
/// AsyncImage) so the share sheet has the actual UIImage to hand to
/// UIActivityViewController; without this, `.savedToPhotosAlbum` and
/// other UIImage-specific share targets wouldn't show up.
struct ChatImageViewer: View {
    let url: URL
    /// Stable message id used to consult `ChatMediaCache` so opening
    /// an already-cached image is instant. nil for fullscreen previews
    /// not tied to a chat message.
    let messageId: UUID?
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var loadFailed = false

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    @State private var dragToDismiss: CGSize = .zero

    @State private var showShare = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            content
                .scaleEffect(scale)
                .offset(x: offset.width + dragToDismiss.width,
                        y: offset.height + dragToDismiss.height)
                .gesture(combinedGesture)
                .gesture(doubleTap)

            VStack {
                topBar
                Spacer()
            }
        }
        .statusBarHidden()
        .task { await loadImage() }
        .sheet(isPresented: $showShare) {
            if let image {
                ShareSheet(items: [image])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else if loadFailed {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundColor(.sacredMuted)
                Text("Couldn't load image.")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }
        } else {
            ProgressView()
                .tint(.sacredGold)
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }

            Spacer()

            if image != nil {
                Button { showShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.black.opacity(0.4)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Composite pinch + pan + dismiss-drag. Pinch updates `scale`; while
    /// zoomed, drag updates `offset` (pan within the image); while at
    /// natural size, drag updates `dragToDismiss` and a far enough drag
    /// closes the sheet.
    private var combinedGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = max(1.0, min(lastScale * value, 5.0))
                }
                .onEnded { _ in
                    lastScale = scale
                    if scale <= 1.05 {
                        withAnimation(.easeOut(duration: 0.2)) {
                            scale = 1.0
                            lastScale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                    }
                },
            DragGesture()
                .onChanged { value in
                    if scale > 1.0 {
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height)
                    } else {
                        // Only respond to vertical drags so a horizontal
                        // swipe (e.g., back gesture muscle memory) doesn't
                        // dismiss accidentally.
                        if abs(value.translation.height) > abs(value.translation.width) {
                            dragToDismiss = CGSize(width: 0, height: value.translation.height)
                        }
                    }
                }
                .onEnded { value in
                    if scale > 1.0 {
                        lastOffset = offset
                    } else if abs(dragToDismiss.height) > 120 {
                        dismiss()
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragToDismiss = .zero
                        }
                    }
                }
        )
    }

    private var doubleTap: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.easeOut(duration: 0.2)) {
                    if scale > 1.0 {
                        scale = 1.0
                        lastScale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        scale = 2.5
                        lastScale = 2.5
                    }
                }
            }
    }

    private func loadImage() async {
        // Prefer the on-disk cached binary when we have a message id —
        // the bubble already downloaded it once, no point fetching again.
        if let messageId,
           let local = await ChatMediaCache.shared.cachedURL(messageId: messageId, remoteUrl: url),
           let img = UIImage(contentsOfFile: local.path) {
            image = img
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: data) {
                image = img
            } else {
                loadFailed = true
            }
        } catch {
            loadFailed = true
        }
    }
}
