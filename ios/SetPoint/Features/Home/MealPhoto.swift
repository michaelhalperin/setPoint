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

    #if DEBUG
    /// A stand-in plate for confirmation previews — not a real meal photo.
    static var demoPlate: MealPhoto {
        let size = CGSize(width: 800, height: 600)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.984, green: 0.965, blue: 0.941, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.949, green: 0.918, blue: 0.875, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 120, y: 50, width: 560, height: 500))
            UIColor(red: 0.835, green: 0.380, blue: 0.227, alpha: 0.45).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 230, y: 150, width: 340, height: 280))
            UIColor(red: 0.431, green: 0.541, blue: 0.404, alpha: 0.55).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 280, y: 210, width: 160, height: 120))
        }
        return MealPhoto.make(from: image.jpegData(compressionQuality: 0.7) ?? Data())
            ?? MealPhoto(base64: "", mediaType: "image/jpeg", preview: image)
    }
    #endif
}

/// Loads meal photos for display. Stored photos arrive as signed URLs that
/// rotate hourly, so images are kept in memory by meal id — a re-rendered list
/// or a fresh URL for the same meal doesn't refetch or flicker. Legacy inline
/// photos decode straight away.
actor MealPhotoCache {
    static let shared = MealPhotoCache()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        cache.countLimit = 60
    }

    func image(for meal: MealSummary) async -> UIImage? {
        if let inline = meal.photoImage { return inline }
        guard let url = meal.remotePhotoURL else { return nil }

        let key = meal.id as NSString
        if let cached = cache.object(forKey: key) { return cached }
        if let running = inFlight[meal.id] { return await running.value }

        let task = Task<UIImage?, Never> { [session] in
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return UIImage(data: data)
        }
        inFlight[meal.id] = task
        let image = await task.value
        inFlight[meal.id] = nil
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}
