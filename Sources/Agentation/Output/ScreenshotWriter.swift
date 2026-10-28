#if os(iOS)
import UIKit

/// Saves a cropped PNG of the app window around an annotation, with the selection outlined.
/// In the Simulator, the file is a normal path on the Mac, so an agent can open it.
@MainActor
enum ScreenshotWriter {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("agentation", isDirectory: true)
    }

    static func capture(_ rect: CGRect, in window: UIWindow, name: String) -> String? {
        let crop = rect.insetBy(dx: -40, dy: -40).intersection(window.bounds).integral
        guard !crop.isNull, crop.width >= 1, crop.height >= 1 else { return nil }

        let format = UIGraphicsImageRendererFormat(for: window.traitCollection)
        let renderer = UIGraphicsImageRenderer(size: crop.size, format: format)
        let data = renderer.pngData { _ in
            let origin = CGPoint(x: -crop.minX, y: -crop.minY)
            window.drawHierarchy(in: CGRect(origin: origin, size: window.bounds.size), afterScreenUpdates: false)
            let outline = UIBezierPath(roundedRect: rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -1, dy: -1),
                                       cornerRadius: 4)
            outline.lineWidth = 2
            UIColor.systemRed.setStroke()
            outline.stroke()
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(name).png")
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            print("[Agentation] Could not save screenshot: \(error)")
            return nil
        }
    }

    static func delete(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}

extension DeviceInfo {
    @MainActor
    static func current(window: UIWindow?) -> DeviceInfo? {
        guard let window else { return nil }
        #if targetEnvironment(simulator)
        let name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.model
        let model = "\(name) Simulator"
        #else
        let model = UIDevice.current.model
        #endif
        let traits = window.traitCollection
        var contentSize = traits.preferredContentSizeCategory.rawValue
        let prefix = "UICTContentSizeCategory"
        if contentSize.hasPrefix(prefix) { contentSize.removeFirst(prefix.count) }
        return DeviceInfo(
            model: model,
            systemVersion: UIDevice.current.systemVersion,
            screenSize: window.bounds.size,
            scale: Double(window.screen.scale),
            isDarkMode: traits.userInterfaceStyle == .dark,
            contentSize: contentSize)
    }
}
#endif
