#if os(macOS)
import Foundation
import CoreGraphics
import ImageIO

/// The bundled, MIT-licensed Bootstrap Icons set, pre-rasterized to tightly-cropped
/// grayscale PNGs (see `pticongen`). Single source of truth for both the renderer
/// (`LabelRenderer.symbolInk`) and the app's symbol picker.
///
/// 0 = ink (black), 255 = background. Images are loaded lazily and cached.
public enum BootstrapIcons {
    /// All icon names (PNG basenames), sorted. Empty if the resource bundle is missing.
    public static let names: [String] = {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "png", subdirectory: "icons") else { return [] }
        return urls.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }()

    /// The grayscale icon image for `name`, or nil if unknown. Cached after first load.
    public static func image(named name: String) -> CGImage? {
        if let hit = cache.withLock({ $0[name] }) { return hit }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "icons"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        cache.withLock { $0[name] = cg }
        return cg
    }

    /// Names containing `query` (case-insensitive); all names when `query` is empty.
    public static func search(_ query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return names }
        return names.filter { $0.range(of: q, options: .caseInsensitive) != nil }
    }

    private static let cache = Mutex<[String: CGImage]>([:])
}

/// Minimal lock wrapper (avoids a platform-version dependency on `OSAllocatedUnfairLock`).
final class Mutex<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func withLock<R>(_ body: (inout Value) -> R) -> R { lock.lock(); defer { lock.unlock() }; return body(&value) }
}
#endif
