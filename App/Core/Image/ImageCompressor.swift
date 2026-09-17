import UIKit

enum ImagePrepError: Error, Equatable {
    case invalidImageData
    case stillTooLarge
}

struct ImageCompressor {
    static let maxDimension: CGFloat = 1280
    static let targetJPEGQuality: CGFloat = 0.7
    static let maximumSafeByteCount = 20 * 1024 * 1024

    static func compress(_ data: Data) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw ImagePrepError.invalidImageData
        }

        let targetSize = scaledSize(for: image.size)
        guard let jpeg = render(image, to: targetSize).jpegData(compressionQuality: targetJPEGQuality) else {
            throw ImagePrepError.invalidImageData
        }

        guard jpeg.count >= maximumSafeByteCount else {
            return jpeg
        }

        for quality in stride(from: 0.6, through: 0.2, by: -0.1) {
            if let candidate = render(image, to: targetSize).jpegData(compressionQuality: quality),
               candidate.count < maximumSafeByteCount {
                return candidate
            }
        }
        throw ImagePrepError.stillTooLarge
    }

    private static func scaledSize(for size: CGSize) -> CGSize {
        let width = size.width
        let height = size.height
        guard width > 0, height > 0 else {
            return size
        }
        let largestSide = max(width, height)
        guard largestSide > maxDimension else {
            return size
        }
        let scale = maxDimension / largestSide
        return CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
    }

    private static func render(_ image: UIImage, to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}