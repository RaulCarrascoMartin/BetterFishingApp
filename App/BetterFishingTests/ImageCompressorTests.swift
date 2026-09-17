import XCTest
import UIKit

@testable import BetterFishing

final class ImageCompressorTests: XCTestCase {
    private static let maxDimension: CGFloat = 1280
    private static let safeSizeLimit = 20 * 1024 * 1024

    func testCompressResizesLargeImageKeepingAspectRatio() throws {
        let source = makeJPEGData(width: 4000, height: 3000)
        let (image, _) = try makeCompressed(from: source)

        XCTAssertLessThanOrEqual(image.size.width, Self.maxDimension)
        XCTAssertLessThanOrEqual(image.size.height, Self.maxDimension)
        XCTAssertEqual(image.size.width, 1280, accuracy: 1)
        XCTAssertEqual(image.size.height, 960, accuracy: 1)
    }

    func testCompressPreservesAspectRatioForWideImage() throws {
        let source = makeJPEGData(width: 4000, height: 1000)
        let (image, _) = try makeCompressed(from: source)

        XCTAssertEqual(image.size.width, 1280, accuracy: 1)
        XCTAssertEqual(image.size.height, 320, accuracy: 1)
    }

    func testCompressProducesJPEGData() throws {
        let source = makeJPEGData(width: 4000, height: 3000)
        let (_, compressed) = try makeCompressed(from: source)

        XCTAssertGreaterThanOrEqual(compressed.count, 3)
        XCTAssertEqual(compressed[0], 0xFF)
        XCTAssertEqual(compressed[1], 0xD8)
        XCTAssertEqual(compressed[2], 0xFF)
    }

    func testCompressOutputIsBelow20MB() throws {
        let source = makeJPEGData(width: 4000, height: 3000)
        let (_, compressed) = try makeCompressed(from: source)

        XCTAssertLessThan(compressed.count, Self.safeSizeLimit)
    }

    func testCompressDoesNotUpscaleSmallImages() throws {
        let source = makeJPEGData(width: 100, height: 80)
        let (image, _) = try makeCompressed(from: source)

        XCTAssertEqual(image.size.width, 100, accuracy: 1)
        XCTAssertEqual(image.size.height, 80, accuracy: 1)
    }

    func testCompressThrowsInvalidImageDataWithoutCrashing() {
        XCTAssertThrowsError(try ImageCompressor.compress(Data([0x00, 0x01, 0x02]))) { error in
            XCTAssertEqual(error as? ImagePrepError, .invalidImageData)
        }
    }

    func testCompressThrowsForEmptyData() {
        XCTAssertThrowsError(try ImageCompressor.compress(Data())) { error in
            XCTAssertEqual(error as? ImagePrepError, .invalidImageData)
        }
    }

    private func makeCompressed(from source: Data) throws -> (image: UIImage, compressed: Data) {
        let compressed = try ImageCompressor.compress(source)
        let image = try XCTUnwrap(UIImage(data: compressed))
        return (image, compressed)
    }

    private func makeJPEGData(width: Int, height: Int, quality: CGFloat = 0.8) -> Data {
        makeImage(width: width, height: height).jpegData(compressionQuality: quality)!
    }

    private func makeImage(width: Int, height: Int) -> UIImage {
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        var index = 0
        for y in 0..<height {
            for x in 0..<width {
                pixels[index] = UInt8((x * 7 + y * 5) % 256)
                pixels[index + 1] = UInt8((x * 11 + y * 3) % 256)
                pixels[index + 2] = UInt8((x * 5 + y * 17) % 256)
                pixels[index + 3] = 255
                index += 4
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let bitmap = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        )
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmap,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
        return UIImage(cgImage: cgImage)
    }
}