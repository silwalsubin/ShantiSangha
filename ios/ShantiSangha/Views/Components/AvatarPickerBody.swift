import SwiftUI
import PhotosUI
import UIKit

/// Reusable avatar picker + circular-crop + JPEG-export pipeline. Both
/// the user's own profile picture (`ProfilePictureGateBody`) and the
/// per-Connection owner-private avatar share this body — they only
/// differ in *where* the bytes get sent, supplied via the `upload`
/// closure.
///
/// Compression: scaled to fit a 512-pt square, exported as JPEG at
/// 0.7 quality. Keeps the average upload under ~200 KB without being
/// visibly blurry on the avatar surfaces (40-pt list rows, 80-pt chat
/// header, 120/160-pt detail screens).
///
/// `initialAvatarUrl` seeds the preview so the existing photo is
/// immediately visible; the user can tap "Choose another" to replace.
/// `footnote` renders below the controls — used by the per-Connection
/// flow to surface the privacy reassurance (`PrivateFootnote`).
struct AvatarPickerBody: View {
    let initialAvatarUrl: String?
    let submitLabel: String
    let upload: (Data) async throws -> Void
    let onSaved: (() -> Void)?
    let footnote: AnyView?
    let removeLabel: String?
    let removeAction: (() async -> Void)?

    @State private var pickerItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var cropScale: CGFloat = 1
    @State private var lastCropScale: CGFloat = 1
    @State private var cropOffset: CGSize = .zero
    @State private var lastCropOffset: CGSize = .zero
    @State private var loadedAvatarUrl: String?
    @State private var showingCamera = false
    @State private var saving = false
    @State private var removing = false
    @State private var errorMessage: String?

    private let maxDimension: CGFloat = 512
    private let jpegQuality: CGFloat = 0.7
    private let avatarSize: CGFloat = 160

    init(
        initialAvatarUrl: String?,
        submitLabel: String,
        upload: @escaping (Data) async throws -> Void,
        onSaved: (() -> Void)? = nil,
        footnote: AnyView? = nil,
        removeLabel: String? = nil,
        removeAction: (() async -> Void)? = nil
    ) {
        self.initialAvatarUrl = initialAvatarUrl
        self.submitLabel = submitLabel
        self.upload = upload
        self.onSaved = onSaved
        self.footnote = footnote
        self.removeLabel = removeLabel
        self.removeAction = removeAction
    }

    var body: some View {
        VStack(spacing: SacredSpacing.l) {
            avatarPreview

            if sourceImage != nil {
                zoomControls
            }

            sourceControls

            if let footnote {
                footnote
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SacredPrimaryButton(
                submitLabel,
                style: .commit,
                isDisabled: sourceImage == nil,
                isLoading: saving
            ) {
                Task { await submit() }
            }

            if let removeAction, let removeLabel {
                Button {
                    Task { await runRemove(removeAction) }
                } label: {
                    if removing {
                        ProgressView().tint(.sacredRed)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    } else {
                        Text(removeLabel)
                            .font(.sacredSmallSemibold)
                            .foregroundColor(.sacredRed)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                }
                .buttonStyle(.plain)
                .disabled(saving || removing)
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await load(newItem) }
        }
        .task(id: initialAvatarUrl) {
            await loadInitialAvatarIfNeeded()
        }
        .fullScreenCover(isPresented: $showingCamera) {
            AvatarCameraPicker { image in
                setSourceImage(image)
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var avatarPreview: some View {
        ZStack {
            if let image = sourceImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: avatarSize, height: avatarSize)
                    .scaleEffect(cropScale)
                    .offset(cropOffset)
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .gesture(cropDragGesture.simultaneously(with: cropZoomGesture))
            } else {
                Circle()
                    .fill(LinearGradient.sacredGoldShinyVertical)
                    .frame(width: avatarSize, height: avatarSize)

                Image(systemName: "person.fill")
                    .font(.system(size: 64, weight: .regular, design: .serif))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .overlay(
            Circle().stroke(Color.sacredGoldDark.opacity(0.25), lineWidth: 1)
        )
        .sacredCardShadow()
    }

    private var sourceControls: some View {
        HStack(spacing: SacredSpacing.m) {
            PhotosPicker(
                selection: $pickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Text(sourceImage == nil ? "Choose photo" : "Choose another")
                    .font(.sacredButtonLabel)
                    .foregroundColor(.sacredGold)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showingCamera = true
                } label: {
                    Text("Take photo")
                        .font(.sacredButtonLabel)
                        .foregroundColor(.sacredGold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var zoomControls: some View {
        VStack(spacing: SacredSpacing.xs) {
            HStack {
                Text("Zoom")
                    .font(.sacredSmallSemibold)
                    .foregroundColor(.sacredTextSecondary)

                Spacer()

                Button("Reset") {
                    resetCrop()
                }
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredMuted)
                .buttonStyle(.plain)
            }

            Slider(
                value: Binding(
                    get: { Double(cropScale) },
                    set: { newValue in
                        cropScale = CGFloat(newValue)
                        lastCropScale = cropScale
                        cropOffset = clampedOffset(cropOffset, scale: cropScale)
                        lastCropOffset = cropOffset
                    }
                ),
                in: 1...3
            )
            .tint(.sacredGold)
        }
    }

    // MARK: - Crop handling

    private var cropDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: lastCropOffset.width + value.translation.width,
                    height: lastCropOffset.height + value.translation.height
                )
                cropOffset = clampedOffset(proposed, scale: cropScale)
            }
            .onEnded { _ in
                lastCropOffset = cropOffset
            }
    }

    private var cropZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                cropScale = min(max(lastCropScale * value, 1), 3)
                cropOffset = clampedOffset(cropOffset, scale: cropScale)
            }
            .onEnded { _ in
                lastCropScale = cropScale
                lastCropOffset = cropOffset
            }
    }

    private func clampedOffset(_ offset: CGSize, scale: CGFloat) -> CGSize {
        guard let image = sourceImage else { return .zero }
        let baseScale = max(avatarSize / image.size.width, avatarSize / image.size.height)
        let displayedSize = CGSize(
            width: image.size.width * baseScale * scale,
            height: image.size.height * baseScale * scale
        )
        let horizontalLimit = max((displayedSize.width - avatarSize) / 2, 0)
        let verticalLimit = max((displayedSize.height - avatarSize) / 2, 0)
        return CGSize(
            width: min(max(offset.width, -horizontalLimit), horizontalLimit),
            height: min(max(offset.height, -verticalLimit), verticalLimit)
        )
    }

    private func resetCrop() {
        cropScale = 1
        lastCropScale = 1
        cropOffset = .zero
        lastCropOffset = .zero
    }

    // MARK: - Picker handling

    private func load(_ item: PhotosPickerItem) async {
        errorMessage = nil
        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                  let original = UIImage(data: raw) else {
                errorMessage = "We couldn't read that image. Try a different one."
                return
            }
            setSourceImage(original)
        } catch {
            errorMessage = "We couldn't load that image. Try a different one."
        }
    }

    private func loadInitialAvatarIfNeeded() async {
        guard sourceImage == nil,
              let rawUrl = initialAvatarUrl,
              loadedAvatarUrl != rawUrl,
              let url = URL(string: rawUrl) else {
            return
        }

        loadedAvatarUrl = rawUrl
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard sourceImage == nil, let image = UIImage(data: data) else { return }
            setSourceImage(image)
        } catch {
            // Keep the icon fallback quiet; choosing a new photo still works.
        }
    }

    private func setSourceImage(_ image: UIImage) {
        sourceImage = image.normalizedForAvatarPicker()
        pickerItem = nil
        errorMessage = nil
        resetCrop()
    }

    /// Aspect-fit downscale to a max bounding square. Skips the scale
    /// step when the image is already small enough so we don't lose
    /// quality on tight crops people pick from their library.
    private func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return image }
        let scale = maxDimension / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func crop(_ image: UIImage) -> UIImage? {
        let size = image.size
        let baseScale = max(avatarSize / size.width, avatarSize / size.height)
        let totalScale = baseScale * cropScale
        let displayedSize = CGSize(width: size.width * totalScale, height: size.height * totalScale)

        let origin = CGPoint(
            x: ((displayedSize.width - avatarSize) / 2 - cropOffset.width) / totalScale,
            y: ((displayedSize.height - avatarSize) / 2 - cropOffset.height) / totalScale
        )
        let side = avatarSize / totalScale
        let cropRect = CGRect(x: origin.x, y: origin.y, width: side, height: side)
            .intersection(CGRect(origin: .zero, size: size))

        guard let cgImage = image.cgImage?.cropping(to: cropRect.applying(.init(scaleX: image.scale, y: image.scale))) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    // MARK: - Submit

    private func runRemove(_ action: () async -> Void) async {
        guard !removing && !saving else { return }
        removing = true
        defer { removing = false }
        await action()
        onSaved?()
    }

    private func submit() async {
        guard let sourceImage, !saving else { return }
        guard let cropped = crop(sourceImage),
              let data = resize(cropped, maxDimension: maxDimension)
                .jpegData(compressionQuality: jpegQuality) else {
            errorMessage = "We couldn't process that image. Try a different one."
            return
        }
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            try await upload(data)
            onSaved?()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "We couldn't upload your photo. Try again."
        }
    }
}

private struct AvatarCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

private extension UIImage {
    func normalizedForAvatarPicker() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
