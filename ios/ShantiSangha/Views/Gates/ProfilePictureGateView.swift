import SwiftUI
import PhotosUI

/// Form body for the profile-picture gate. Shows a circular preview of the
/// pick (or a placeholder with the user's initials), a PhotosPicker to
/// choose / re-choose, and a Continue button that compresses the image to
/// a reasonable JPEG and uploads via `ProfileService.uploadAvatar`.
///
/// Compression: scaled to fit a 512-pt square (largest dimension), exported
/// as JPEG at 0.7 quality. Keeps the average upload under ~200 KB without
/// being visibly blurry on the avatar surfaces (40-pt and 80-pt circles in
/// the Friends list and chat header).
struct ProfilePictureGateBody: View {
    @EnvironmentObject private var profile: ProfileService

    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedData: Data?
    @State private var pickedImage: UIImage?
    @State private var saving = false
    @State private var errorMessage: String?

    private let maxDimension: CGFloat = 512
    private let jpegQuality: CGFloat = 0.7
    private let avatarSize: CGFloat = 160

    var body: some View {
        VStack(spacing: SacredSpacing.l) {
            avatarPreview

            PhotosPicker(
                selection: $pickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Text(pickedImage == nil ? "Choose photo" : "Pick a different one")
                    .font(.sacredButtonLabel)
                    .foregroundColor(.sacredGold)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SacredPrimaryButton(
                "Continue",
                style: .commit,
                isDisabled: pickedData == nil,
                isLoading: saving
            ) {
                Task { await submit() }
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadAndCompress(newItem) }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var avatarPreview: some View {
        ZStack {
            Circle()
                .fill(LinearGradient.sacredGoldShinyVertical)
                .frame(width: avatarSize, height: avatarSize)

            if let image = pickedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())
            } else {
                Text(initials)
                    .font(.system(size: 48, weight: .semibold, design: .serif))
                    .foregroundColor(.white)
            }
        }
        .overlay(
            Circle().stroke(Color.sacredGoldDark.opacity(0.25), lineWidth: 1)
        )
        .sacredCardShadow()
    }

    private var initials: String {
        let name = (profile.profile?.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "·" }
        let parts = name.split(separator: " ").compactMap(\.first).map(String.init)
        return parts.prefix(2).joined().uppercased()
    }

    // MARK: - Picker handling

    private func loadAndCompress(_ item: PhotosPickerItem) async {
        errorMessage = nil
        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                  let original = UIImage(data: raw) else {
                errorMessage = "We couldn't read that image. Try a different one."
                return
            }
            let resized = resize(original, maxDimension: maxDimension)
            guard let jpeg = resized.jpegData(compressionQuality: jpegQuality) else {
                errorMessage = "We couldn't process that image. Try a different one."
                return
            }
            pickedImage = resized
            pickedData = jpeg
        } catch {
            errorMessage = "We couldn't load that image. Try a different one."
        }
    }

    /// Aspect-fit downscale to a max bounding square. Skips the scale step
    /// when the image is already small enough so we don't lose quality on
    /// tight crops people pick from their library.
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

    // MARK: - Submit

    private func submit() async {
        guard let data = pickedData, !saving else { return }
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            try await profile.uploadAvatar(jpegData: data)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "We couldn't upload your photo. Try again."
        }
    }
}
