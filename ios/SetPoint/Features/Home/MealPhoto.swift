import UIKit

/// A meal photo the user picked, downscaled and JPEG-encoded for upload (§5.5 —
/// the backend feeds `data` straight to the vision model).
struct MealPhoto: Equatable {
    let base64: String
    let mediaType: String
    let preview: UIImage

    static func == (lhs: MealPhoto, rhs: MealPhoto) -> Bool { lhs.base64 == rhs.base64 }

    /// Resize to ~1024px on the long edge and compress. Returns nil if the data
    /// isn't a decodable image.
    static func make(from data: Data) -> MealPhoto? {
        guard let image = UIImage(data: data) else { return nil }

        let maxEdge: CGFloat = 1024
        let longest = max(image.size.width, image.size.height)
        let ratio = longest > maxEdge ? maxEdge / longest : 1
        let target = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }

        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return nil }
        return MealPhoto(base64: jpeg.base64EncodedString(), mediaType: "image/jpeg", preview: resized)
    }
}
