import XCTest
@testable import PTouchKit

#if os(macOS)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Verifies that an image cell renders the same whether it references a file
/// (`imagePath`) or carries baked-in pixels (`imageData`), and that baking via
/// `downsizedImagePNG` round-trips.
final class EmbeddedImageTests: XCTestCase {
    private let renderer = LabelRenderer()

    /// A small test PNG: left half black, right half white.
    private func makeTestPNG() -> Data {
        let w = 200, h = 100
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
        let cg = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cg, nil); CGImageDestinationFinalize(dest)
        return out as Data
    }

    private func inkDots(_ label: RenderedLabel) -> Int {
        label.rows.reduce(0) { acc, row in acc + row.reduce(0) { $0 + $1.nonzeroBitCount } }
    }

    func testPathAndDataRenderEquivalently() throws {
        let png = makeTestPNG()
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".png")
        try png.write(to: url); defer { try? FileManager.default.removeItem(at: url) }

        let pathCell = LabelCell(kind: .image, imagePath: url.path)
        let dataCell = LabelCell(kind: .image, imageData: png)

        let fromPath = try XCTUnwrap(renderer.render(cells: [pathCell]))
        let fromData = try XCTUnwrap(renderer.render(cells: [dataCell]))

        XCTAssertGreaterThan(inkDots(fromPath), 0)
        XCTAssertEqual(fromPath.lengthDots, fromData.lengthDots, "path vs embedded width differ")
        XCTAssertEqual(inkDots(fromPath), inkDots(fromData), "path vs embedded ink differ")
    }

    func testBakeRoundTrips() throws {
        let png = makeTestPNG()
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".png")
        try png.write(to: url); defer { try? FileManager.default.removeItem(at: url) }

        let pathCell = LabelCell(kind: .image, imagePath: url.path)
        let baked = try XCTUnwrap(renderer.downsizedImagePNG(for: pathCell), "bake produced no data")
        XCTAssertLessThan(baked.count, 20_000, "downsized image should be small")

        // A baked cell (no path) must still render, matching the original.
        let bakedCell = LabelCell(kind: .image, imageData: baked)
        let original = try XCTUnwrap(renderer.render(cells: [pathCell]))
        let rebaked = try XCTUnwrap(renderer.render(cells: [bakedCell]))
        XCTAssertEqual(original.lengthDots, rebaked.lengthDots)
        XCTAssertGreaterThan(inkDots(rebaked), 0)
    }

    func testDownsizedImageIsNilForNonImageCell() {
        XCTAssertNil(renderer.downsizedImagePNG(for: LabelCell(kind: .text, text: "hi")))
    }
}
#endif
