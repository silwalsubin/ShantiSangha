import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers
import QuickLook

/// Owner-private keepsakes attached to a Connection. Splits into two
/// section cards — MEDIA (photos + videos in a thumbnail grid) and
/// FILES (everything else as a list). Sections only render when they
/// have items; otherwise a single Add CTA stands in.
///
/// Data flow:
/// - List loads on appear and after every successful mutation.
/// - Upload is a three-step handshake (presigned PUT → S3 → commit)
///   handled by `ConnectionsAPI.uploadAttachment`.
/// - Tapping a media tile opens an in-app full-screen viewer (image
///   pinch-zoom / video player). Tapping a file row opens it via the
///   system handler (Safari for PDFs, Files app fallback otherwise).
/// - Long-press / overflow menu offers caption edit + delete.
struct ConnectionAttachmentsView: View {
    let connectionId: UUID

    @State private var attachments: [ConnectionAttachment] = []
    @State private var pendingItems: [PendingAttachment] = []
    @State private var loading = false
    @State private var didLoadOnce = false
    @State private var errorMessage: String?

    @State private var showAddSheet = false
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var photoSelections: [PhotosPickerItem] = []

    @State private var captionTarget: ConnectionAttachment?
    @State private var deleteTarget: ConnectionAttachment?
    @State private var mediaViewerTarget: ConnectionAttachment?
    @State private var fileQuickLookURL: URL?
    @State private var savingOfflineIds: Set<UUID> = []

    @StateObject private var cache = AttachmentCache.shared

    var body: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.l) {
            if !mediaItems.isEmpty || !pendingMediaItems.isEmpty {
                mediaSection
            }
            if !fileItems.isEmpty || !pendingFileItems.isEmpty {
                filesSection
                    .padding(.horizontal, SacredSpacing.m)
            }
            if attachments.isEmpty && pendingItems.isEmpty && didLoadOnce && !loading {
                emptyCTA
                    .padding(.horizontal, SacredSpacing.m)
            }
            if didLoadOnce {
                PrivateFootnote()
                    .padding(.horizontal, SacredSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.sacredMicro)
                    .foregroundColor(.sacredRed)
                    .padding(.horizontal, SacredSpacing.m)
            }
        }
        .task(id: connectionId) {
            await load()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.sacredGold)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            SacredChoiceSheet(
                title: "Add media or files",
                prompt: "Choose what to add.",
                choices: [
                    SacredChoice(icon: "photo", title: "Photo or video") {
                        showAddSheet = false
                        showPhotoPicker = true
                    },
                    SacredChoice(icon: "doc", title: "File") {
                        showAddSheet = false
                        showFilePicker = true
                    },
                ]
            )
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoSelections,
            maxSelectionCount: 10,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared())
        .onChange(of: photoSelections) { _, picks in
            guard !picks.isEmpty else { return }
            let snapshot = picks
            photoSelections = []
            Task { await uploadPhotoItems(snapshot) }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await uploadFileURLs(urls) }
            case .failure(let error):
                errorMessage = "Couldn't pick files. \(error.localizedDescription)"
            }
        }
        .sheet(item: $captionTarget) { target in
            AttachmentCaptionSheet(
                attachment: target,
                onSave: { caption in await saveCaption(target: target, caption: caption) })
        }
        .sheet(item: $mediaViewerTarget) { target in
            AttachmentMediaViewer(attachment: target)
        }
        .quickLookPreview($fileQuickLookURL)
        .confirmationDialog(
            deleteConfirmTitle,
            isPresented: deleteConfirmBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    Task { await deleteAttachment(target) }
                }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Removed from your circle. The original isn't touched.")
        }
    }

    // MARK: - Sections

    private var mediaSection: some View {
        // Edge-to-edge Apple-Photos-style grid: 3 cols, 2pt gutters, square
        // tiles with no corner radius or border. The screen title carries
        // the section name so we don't render an inline "MEDIA" header.
        LazyVGrid(columns: gridColumns, spacing: 2) {
            ForEach(pendingMediaItems) { pending in
                PendingMediaTile(pending: pending)
            }
            ForEach(mediaItems) { item in
                MediaTile(
                    attachment: item,
                    isSavingOffline: savingOfflineIds.contains(item.id))
                    .onTapGesture { mediaViewerTarget = item }
                    .contextMenu { contextActions(for: item) }
            }
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("FILES")
            SacredListCard {
                VStack(spacing: 0) {
                    ForEach(pendingFileItems) { pending in
                        PendingFileRow(pending: pending)
                        if !fileItems.isEmpty || pending.id != pendingFileItems.last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                    ForEach(Array(fileItems.enumerated()), id: \.element.id) { index, item in
                        FileRow(
                            attachment: item,
                            isSavingOffline: savingOfflineIds.contains(item.id),
                            onTap: { handleFileTap(item) })
                            .contextMenu { contextActions(for: item) }
                        if index < fileItems.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
        }
    }

    private var emptyCTA: some View {
        // Screen title already says "Media & Files" — no inline section
        // header needed. Empty state is its own focused moment. The
        // privacy footnote is rendered once at the body level so it
        // appears in both empty and populated states.
        SacredCard {
            SacredEmptyState(
                icon: "photo.on.rectangle.angled",
                title: "Hold onto a moment.",
                subtitle: "Photos, videos, or files you want to remember about them.",
                actionLabel: "Add something") { showAddSheet = true }
        }
    }

    @ViewBuilder
    private func contextActions(for item: ConnectionAttachment) -> some View {
        Button {
            captionTarget = item
        } label: {
            Label(item.caption == nil ? "Add caption" : "Edit caption",
                  systemImage: "text.alignleft")
        }
        if cache.isOffline(item.id) {
            Button {
                cache.removeOffline(item)
            } label: {
                Label("Remove from offline", systemImage: "icloud.slash")
            }
        } else {
            Button {
                Task { await saveOffline(item) }
            } label: {
                Label("Save for offline", systemImage: "arrow.down.circle")
            }
        }
        if let url = URL(string: item.downloadUrl) {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        Button(role: .destructive) {
            deleteTarget = item
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func saveOffline(_ item: ConnectionAttachment) async {
        savingOfflineIds.insert(item.id)
        defer { savingOfflineIds.remove(item.id) }
        do {
            try await cache.saveOffline(item)
        } catch {
            if !error.isCancellation {
                errorMessage = "Couldn't save \(item.fileName) offline. Try again."
            }
        }
    }

    /// Resolves the best URL for tapping a file row. Prefers the local
    /// offline copy when present so the file opens in QuickLook without
    /// network; otherwise punts to the system handler (Safari for PDFs,
    /// etc.) via the presigned URL.
    private func handleFileTap(_ item: ConnectionAttachment) {
        if let local = cache.offlineFileURL(for: item) {
            fileQuickLookURL = local
            return
        }
        if let url = URL(string: item.downloadUrl) {
            UIApplication.shared.open(url)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.sacredSectionLabel)
            .foregroundColor(.sacredLabel)
            .padding(.horizontal, 4)
    }

    private var gridColumns: [GridItem] {
        // 3-column Apple-Photos grid. 2pt gutters match the LazyVGrid
        // row spacing for a uniform tight checkerboard look.
        Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    }

    // MARK: - Derived state

    private var mediaItems: [ConnectionAttachment] {
        attachments.filter { $0.kind == .media }
    }

    private var fileItems: [ConnectionAttachment] {
        attachments.filter { $0.kind == .file }
    }

    private var pendingMediaItems: [PendingAttachment] {
        pendingItems.filter { $0.kind == .media }
    }

    private var pendingFileItems: [PendingAttachment] {
        pendingItems.filter { $0.kind == .file }
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } })
    }

    private var deleteConfirmTitle: String {
        guard let deleteTarget else { return "Delete this?" }
        if let caption = deleteTarget.caption, !caption.isEmpty {
            return "Delete \"\(caption)\"?"
        }
        return "Delete \(deleteTarget.fileName)?"
    }

    // MARK: - Network

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            attachments = try await ConnectionsAPI.listAttachments(connectionId)
            errorMessage = nil
            didLoadOnce = true
        } catch {
            if !error.isCancellation {
                errorMessage = "Couldn't load. Pull to refresh."
                didLoadOnce = true
            }
        }
    }

    private func uploadPhotoItems(_ items: [PhotosPickerItem]) async {
        // Each upload runs serially so the user sees pending tiles
        // resolve in order and we don't race the server. The pending
        // tiles themselves provide the per-item progress feedback.
        for item in items {
            await uploadOnePhoto(item)
        }
    }

    private func uploadOnePhoto(_ item: PhotosPickerItem) async {
        let data: Data?
        do {
            data = try await item.loadTransferable(type: Data.self)
        } catch {
            if !error.isCancellation {
                errorMessage = "Couldn't read that photo. \(error.localizedDescription)"
            }
            return
        }
        guard let data else {
            errorMessage = "Couldn't read that photo."
            return
        }

        let (contentType, fileName) = mediaMetadata(for: item)
        let preview = contentType.hasPrefix("image/") ? UIImage(data: data) : nil

        let pending = PendingAttachment(
            id: UUID(),
            kind: .media,
            contentType: contentType,
            fileName: fileName,
            preview: preview)
        pendingItems.insert(pending, at: 0)

        do {
            let real = try await ConnectionsAPI.uploadAttachment(
                connectionId,
                data: data,
                contentType: contentType,
                fileName: fileName)
            // Seed the cache so the real tile renders the same image
            // the user just uploaded — no S3 round-trip on first paint.
            if let preview {
                cache.cacheThumbnail(preview, for: real.id)
            }
            attachments.insert(real, at: 0)
            pendingItems.removeAll { $0.id == pending.id }
            errorMessage = nil
        } catch {
            pendingItems.removeAll { $0.id == pending.id }
            if !error.isCancellation {
                errorMessage = "Couldn't upload \(fileName). Try again."
            }
        }
    }

    private func uploadFileURLs(_ urls: [URL]) async {
        for url in urls {
            await uploadOneFile(url)
        }
    }

    private func uploadOneFile(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if !error.isCancellation {
                errorMessage = "Couldn't read \(url.lastPathComponent)."
            }
            return
        }

        let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey])
        let contentType = resourceValues?.contentType?.preferredMIMEType ?? "application/octet-stream"
        let fileName = url.lastPathComponent

        let pending = PendingAttachment(
            id: UUID(),
            kind: .file,
            contentType: contentType,
            fileName: fileName,
            preview: nil)
        pendingItems.insert(pending, at: 0)

        do {
            let real = try await ConnectionsAPI.uploadAttachment(
                connectionId,
                data: data,
                contentType: contentType,
                fileName: fileName)
            attachments.insert(real, at: 0)
            pendingItems.removeAll { $0.id == pending.id }
            errorMessage = nil
        } catch {
            pendingItems.removeAll { $0.id == pending.id }
            if !error.isCancellation {
                errorMessage = "Couldn't upload \(fileName). Try again."
            }
        }
    }

    private func saveCaption(target: ConnectionAttachment, caption: String) async {
        // Empty string clears the caption server-side; trim first so a
        // user typing only whitespace doesn't accidentally pin it.
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let updated = try await ConnectionsAPI.updateAttachment(
                connectionId,
                attachmentId: target.id,
                request: UpdateConnectionAttachmentRequest(caption: trimmed))
            replaceInPlace(updated)
            errorMessage = nil
            captionTarget = nil
        } catch {
            errorMessage = "Couldn't save caption. Try again."
        }
    }

    private func deleteAttachment(_ target: ConnectionAttachment) async {
        let id = target.id
        do {
            try await ConnectionsAPI.deleteAttachment(connectionId, attachmentId: id)
            attachments.removeAll { $0.id == id }
            cache.purge(target)
            errorMessage = nil
            deleteTarget = nil
        } catch {
            errorMessage = "Couldn't delete. Try again."
        }
    }

    private func replaceInPlace(_ updated: ConnectionAttachment) {
        if let i = attachments.firstIndex(where: { $0.id == updated.id }) {
            attachments[i] = updated
        }
    }

    /// Pull a usable MIME type and filename out of a PhotosPickerItem.
    /// `supportedContentTypes` returns the asset's UTType lineage; the
    /// most-preferred entry is the actual format. Falls back to
    /// generic image/jpeg for stills, video/mp4 for movies.
    private func mediaMetadata(for item: PhotosPickerItem) -> (contentType: String, fileName: String) {
        let utType = item.supportedContentTypes.first
        let mime = utType?.preferredMIMEType
        let ext = utType?.preferredFilenameExtension
        let stamp = Self.timestampFormatter.string(from: Date())
        let isVideo = utType?.conforms(to: .movie) == true || mime?.hasPrefix("video/") == true

        if let mime, let ext {
            let prefix = isVideo ? "video" : "photo"
            return (mime, "\(prefix)-\(stamp).\(ext)")
        }
        if isVideo {
            return ("video/mp4", "video-\(stamp).mp4")
        }
        return ("image/jpeg", "photo-\(stamp).jpg")
    }

    private static let timestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        return df
    }()
}

// MARK: - Pending (optimistic) representation

/// Lightweight in-flight upload — the tile we render immediately after
/// the user picks a photo / file, before the server has committed the
/// row. Carries the local preview image (for photos) so the grid can
/// show the real thing right away with a spinner overlay instead of a
/// vague footer line.
struct PendingAttachment: Identifiable, Equatable {
    let id: UUID
    let kind: ConnectionAttachmentKind
    let contentType: String
    let fileName: String
    let preview: UIImage?

    static func == (lhs: PendingAttachment, rhs: PendingAttachment) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Tile views

private struct MediaTile: View {
    let attachment: ConnectionAttachment
    let isSavingOffline: Bool

    @State private var thumbnail: UIImage?
    @StateObject private var cache = AttachmentCache.shared

    var body: some View {
        ZStack {
            thumbnailLayer
            overlay
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .task(id: thumbnailTaskKey) {
            if let cached = cache.cachedThumbnail(for: attachment.id) {
                thumbnail = cached
                return
            }
            thumbnail = await cache.loadThumbnail(for: attachment)
        }
    }

    /// Re-runs the thumbnail load when the attachment changes OR when
    /// it transitions to/from offline (so a video tile can refresh
    /// from "placeholder gradient" to a real frame the moment its
    /// local copy lands on disk).
    private var thumbnailTaskKey: String {
        "\(attachment.id):\(cache.isOffline(attachment.id))"
    }

    @ViewBuilder
    private var thumbnailLayer: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else if attachment.contentType.hasPrefix("video/") {
            // Warm placeholder reads as "media you saved" while the
            // tile waits for an offline-save to seed a real frame.
            LinearGradient(
                colors: [Color.sacredGoldDark.opacity(0.35), Color.sacredBgCard],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
        } else {
            Color.sacredBgCard
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if attachment.contentType.hasPrefix("video/") {
            Image(systemName: "play.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }

        VStack {
            HStack {
                Spacer()
                offlineBadge
            }
            Spacer()
            captionLine
        }
        .padding(6)
    }

    @ViewBuilder
    private var offlineBadge: some View {
        if isSavingOffline {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
                .padding(4)
                .background(Circle().fill(Color.black.opacity(0.45)))
        } else if cache.isOffline(attachment.id) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.sacredGoldShine)
                .padding(2)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
    }

    @ViewBuilder
    private var captionLine: some View {
        if let caption = attachment.caption, !caption.isEmpty {
            Text(caption)
                .font(.sacredMicroBold)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom))
        }
    }
}

/// Optimistic counterpart to `MediaTile` — same container chrome and
/// caption styling, but shows the locally-decoded preview (for photos)
/// or the warm gradient (for videos) with a centered progress spinner
/// while the upload is in flight. Disappears as soon as the real
/// attachment lands in the list.
private struct PendingMediaTile: View {
    let pending: PendingAttachment

    var body: some View {
        ZStack {
            preview
            Color.black.opacity(0.35)
            ProgressView()
                .controlSize(.regular)
                .tint(.white)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }

    @ViewBuilder
    private var preview: some View {
        if let image = pending.preview {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            // Video — no cheap inline frame extraction during upload;
            // use the same warm placeholder MediaTile uses for the
            // not-yet-cached case.
            LinearGradient(
                colors: [Color.sacredGoldDark.opacity(0.35), Color.sacredBgCard],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
        }
    }
}

private struct FileRow: View {
    let attachment: ConnectionAttachment
    let isSavingOffline: Bool
    let onTap: () -> Void

    @StateObject private var cache = AttachmentCache.shared

    var body: some View {
        Button(action: onTap) { rowBody }
            .buttonStyle(.plain)
    }

    private var rowBody: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.sacredGold)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.sacredGold.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLabel)
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(secondaryLine)
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            trailingIcon
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var trailingIcon: some View {
        if isSavingOffline {
            ProgressView()
                .controlSize(.small)
                .tint(.sacredGold)
        } else if cache.isOffline(attachment.id) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.sacredGoldShine)
        } else {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.sacredMuted.opacity(0.6))
        }
    }

    private var primaryLabel: String {
        if let caption = attachment.caption, !caption.isEmpty {
            return caption
        }
        return attachment.fileName
    }

    private var secondaryLine: String {
        let parts = [attachment.fileName, ByteCountFormatter.string(
            fromByteCount: attachment.byteSize,
            countStyle: .file)]
        // If primaryLabel == fileName we'd be repeating it; show size only.
        if attachment.caption == nil || attachment.caption?.isEmpty == true {
            return parts[1]
        }
        return parts.joined(separator: " · ")
    }

    private var iconName: String {
        FileIconResolver.icon(for: attachment.contentType)
    }
}

/// Optimistic counterpart to `FileRow` — same chrome, but the trailing
/// affordance is a spinner instead of the open-arrow / offline badge,
/// and the row is not tappable while the upload is in flight. Falls
/// off the screen as soon as the real attachment commits.
private struct PendingFileRow: View {
    let pending: PendingAttachment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: FileIconResolver.icon(for: pending.contentType))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.sacredGold)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.sacredGold.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(pending.fileName)
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Uploading…")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
            }

            Spacer(minLength: 0)

            ProgressView()
                .controlSize(.small)
                .tint(.sacredGold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(0.85)
    }
}

/// Shared content-type → SF Symbol mapping used by both the real and
/// pending file rows so they read as the same kind during the
/// optimistic-to-committed handoff.
private enum FileIconResolver {
    static func icon(for contentType: String) -> String {
        let ct = contentType.lowercased()
        if ct.contains("pdf") { return "doc.richtext" }
        if ct.contains("audio") { return "waveform" }
        if ct.contains("zip") || ct.contains("compressed") { return "doc.zipper" }
        if ct.contains("text") || ct.contains("plain") { return "doc.text" }
        if ct.contains("word") || ct.contains("document") { return "doc.text.fill" }
        if ct.contains("sheet") || ct.contains("excel") { return "tablecells" }
        if ct.contains("presentation") { return "rectangle.on.rectangle" }
        return "doc"
    }
}

// MARK: - Caption sheet

private struct AttachmentCaptionSheet: View {
    let attachment: ConnectionAttachment
    let onSave: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var captionDraft: String = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ZStack {
                SacredBackground().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: SacredSpacing.l) {
                        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                            Text("CAPTION")
                                .font(.sacredSectionLabel)
                                .foregroundColor(.sacredLabel)
                                .padding(.horizontal, 4)

                            SacredListCard {
                                ZStack(alignment: .topLeading) {
                                    if captionDraft.isEmpty {
                                        Text("What this is, in a few words.")
                                            .font(.sacredText)
                                            .foregroundColor(.sacredMutedLight)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 18)
                                    }
                                    TextEditor(text: $captionDraft)
                                        .font(.sacredText)
                                        .foregroundColor(.sacredText)
                                        .scrollContentBackground(.hidden)
                                        .background(Color.clear)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .frame(minHeight: 120)
                                }
                            }

                            Text(attachment.fileName)
                                .font(.sacredMicro)
                                .foregroundColor(.sacredMuted)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, SacredSpacing.m)
                    .padding(.vertical, SacredSpacing.l)
                }
            }
            .navigationTitle("Edit caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.sacredGold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            saving = true
                            await onSave(captionDraft)
                            saving = false
                        }
                    } label: {
                        if saving {
                            ProgressView().controlSize(.small).tint(.sacredGold)
                        } else {
                            Text("Save")
                                .font(.sacredButtonLabel)
                                .foregroundColor(.sacredGold)
                        }
                    }
                    .disabled(saving)
                }
            }
        }
        .onAppear {
            captionDraft = attachment.caption ?? ""
        }
    }
}

// MARK: - Media viewer

private struct AttachmentMediaViewer: View {
    let attachment: ConnectionAttachment

    @Environment(\.dismiss) private var dismiss
    @State private var imageZoom: CGFloat = 1.0
    @State private var imageZoomBase: CGFloat = 1.0

    /// Local file URL when the attachment is saved offline, else the
    /// presigned remote URL. Lets full-screen viewing work without
    /// network for offline-saved keepsakes.
    private var sourceURL: URL? {
        if let local = AttachmentCache.shared.offlineFileURL(for: attachment) {
            return local
        }
        return URL(string: attachment.downloadUrl)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            VStack {
                topBar
                Spacer()
                if let caption = attachment.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.sacredText)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, SacredSpacing.l)
                        .padding(.vertical, SacredSpacing.m)
                        .background(Color.black.opacity(0.45))
                }
            }
        }
        .statusBar(hidden: true)
    }

    @ViewBuilder
    private var content: some View {
        if attachment.contentType.hasPrefix("video/"),
           let url = sourceURL {
            // Lift the AVPlayer out of `body` so SwiftUI rebuilds (e.g.
            // dismissal animation, status bar updates) don't restart
            // playback by handing the player view a fresh instance.
            VideoPlayerHost(url: url)
                .ignoresSafeArea()
        } else if let url = sourceURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(imageZoom)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    imageZoom = max(1.0, min(4.0, imageZoomBase * value))
                                }
                                .onEnded { _ in
                                    imageZoomBase = imageZoom
                                })
                        .onTapGesture(count: 2) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                imageZoom = imageZoom > 1.0 ? 1.0 : 2.5
                                imageZoomBase = imageZoom
                            }
                        }
                case .failure:
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.6))
                default:
                    ProgressView().tint(.white)
                }
            }
        } else {
            Color.black
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
        }
        .padding(.horizontal, SacredSpacing.m)
        .padding(.top, SacredSpacing.m)
    }
}

private struct VideoPlayerHost: View {
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
