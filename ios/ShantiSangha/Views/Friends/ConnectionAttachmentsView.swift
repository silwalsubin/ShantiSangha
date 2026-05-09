import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

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
    @State private var loading = false
    @State private var didLoadOnce = false
    @State private var errorMessage: String?

    @State private var uploadInFlight = 0
    @State private var totalUploads = 0
    @State private var currentUploadIndex = 0

    @State private var showAddDialog = false
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var photoSelections: [PhotosPickerItem] = []

    @State private var captionTarget: ConnectionAttachment?
    @State private var deleteTarget: ConnectionAttachment?
    @State private var mediaViewerTarget: ConnectionAttachment?

    var body: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.l) {
            if !mediaItems.isEmpty {
                mediaSection
            }
            if !fileItems.isEmpty {
                filesSection
            }
            if attachments.isEmpty && didLoadOnce && !loading {
                emptyCTA
            }
            if !attachments.isEmpty {
                addRow
            }
            if uploadInFlight > 0 {
                uploadProgressLine
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.sacredMicro)
                    .foregroundColor(.sacredRed)
                    .padding(.horizontal, 4)
            }
        }
        .task(id: connectionId) {
            await load()
        }
        .confirmationDialog(
            "Add a keepsake",
            isPresented: $showAddDialog,
            titleVisibility: .visible
        ) {
            Button("Photo or video") { showPhotoPicker = true }
            Button("File") { showFilePicker = true }
            Button("Cancel", role: .cancel) {}
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
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("MEDIA")
            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(mediaItems) { item in
                    MediaTile(attachment: item)
                        .onTapGesture { mediaViewerTarget = item }
                        .contextMenu { contextActions(for: item) }
                }
            }
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("FILES")
            SacredListCard {
                VStack(spacing: 0) {
                    ForEach(Array(fileItems.enumerated()), id: \.element.id) { index, item in
                        FileRow(attachment: item)
                            .contextMenu { contextActions(for: item) }
                        if index < fileItems.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
        }
    }

    private var addRow: some View {
        Button {
            showAddDialog = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("Add a keepsake")
                    .font(.sacredSmallSemibold)
                Spacer()
            }
            .foregroundColor(.sacredGold)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.sacredGold.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyCTA: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("KEEPSAKES")
            SacredCard {
                SacredEmptyState(
                    icon: "photo.on.rectangle.angled",
                    title: "Hold onto a moment.",
                    subtitle: "Photos, videos, or files you want to remember about them.",
                    actionLabel: "Add something") { showAddDialog = true }
            }

            Text("Only you can see this.")
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
                .padding(.horizontal, 4)
        }
    }

    private var uploadProgressLine: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(.sacredGold)
            Text(uploadProgressText)
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
        }
        .padding(.horizontal, 4)
    }

    private var uploadProgressText: String {
        if totalUploads <= 1 { return "Uploading…" }
        return "Uploading \(currentUploadIndex) of \(totalUploads)…"
    }

    @ViewBuilder
    private func contextActions(for item: ConnectionAttachment) -> some View {
        Button {
            captionTarget = item
        } label: {
            Label(item.caption == nil ? "Add caption" : "Edit caption",
                  systemImage: "text.alignleft")
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.sacredSectionLabel)
            .foregroundColor(.sacredLabel)
            .padding(.horizontal, 4)
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
    }

    // MARK: - Derived state

    private var mediaItems: [ConnectionAttachment] {
        attachments.filter { $0.kind == .media }
    }

    private var fileItems: [ConnectionAttachment] {
        attachments.filter { $0.kind == .file }
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } })
    }

    private var deleteConfirmTitle: String {
        guard let deleteTarget else { return "Delete keepsake?" }
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
                errorMessage = "Couldn't load keepsakes. Pull to refresh."
                didLoadOnce = true
            }
        }
    }

    private func uploadPhotoItems(_ items: [PhotosPickerItem]) async {
        totalUploads = items.count
        uploadInFlight = items.count
        defer {
            uploadInFlight = 0
            totalUploads = 0
            currentUploadIndex = 0
        }

        for (index, item) in items.enumerated() {
            currentUploadIndex = index + 1
            await uploadOnePhoto(item)
            uploadInFlight = max(0, uploadInFlight - 1)
        }
        await load()
    }

    private func uploadOnePhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Couldn't read that photo."
                return
            }
            let (contentType, suggestedName) = mediaMetadata(for: item)
            _ = try await ConnectionsAPI.uploadAttachment(
                connectionId,
                data: data,
                contentType: contentType,
                fileName: suggestedName)
            errorMessage = nil
        } catch {
            if !error.isCancellation {
                errorMessage = "Couldn't upload one of the photos. Try again."
            }
        }
    }

    private func uploadFileURLs(_ urls: [URL]) async {
        totalUploads = urls.count
        uploadInFlight = urls.count
        defer {
            uploadInFlight = 0
            totalUploads = 0
            currentUploadIndex = 0
        }

        for (index, url) in urls.enumerated() {
            currentUploadIndex = index + 1
            await uploadOneFile(url)
            uploadInFlight = max(0, uploadInFlight - 1)
        }
        await load()
    }

    private func uploadOneFile(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey])
            let contentType = resourceValues?.contentType?.preferredMIMEType ?? "application/octet-stream"
            _ = try await ConnectionsAPI.uploadAttachment(
                connectionId,
                data: data,
                contentType: contentType,
                fileName: url.lastPathComponent)
            errorMessage = nil
        } catch {
            if !error.isCancellation {
                errorMessage = "Couldn't upload \(url.lastPathComponent). Try again."
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

// MARK: - Tile views

private struct MediaTile: View {
    let attachment: ConnectionAttachment

    var body: some View {
        ZStack {
            thumbnail
            overlay
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.sacredGold.opacity(0.18), lineWidth: 0.5))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if attachment.contentType.hasPrefix("image/"),
           let url = URL(string: attachment.downloadUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.sacredBgCard
                }
            }
        } else {
            // Video — no cheap inline frame extraction. A warm placeholder
            // tile reads as "media you saved"; the play overlay below
            // makes the kind unambiguous.
            LinearGradient(
                colors: [Color.sacredGoldDark.opacity(0.35), Color.sacredBgCard],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
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
        if let caption = attachment.caption, !caption.isEmpty {
            VStack {
                Spacer()
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
}

private struct FileRow: View {
    let attachment: ConnectionAttachment

    var body: some View {
        if let url = URL(string: attachment.downloadUrl) {
            Link(destination: url) { rowBody }
                .buttonStyle(.plain)
        } else {
            rowBody
        }
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

            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.sacredMuted.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
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
        let ct = attachment.contentType.lowercased()
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
           let url = URL(string: attachment.downloadUrl) {
            // Lift the AVPlayer out of `body` so SwiftUI rebuilds (e.g.
            // dismissal animation, status bar updates) don't restart
            // playback by handing the player view a fresh instance.
            VideoPlayerHost(url: url)
                .ignoresSafeArea()
        } else if let url = URL(string: attachment.downloadUrl) {
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
