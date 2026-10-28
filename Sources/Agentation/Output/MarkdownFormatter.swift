import Foundation
import CoreGraphics

/// Device context printed at the top of copied feedback.
struct DeviceInfo: Equatable {
    var model: String
    var systemVersion: String
    var screenSize: CGSize
    var scale: Double
    var isDarkMode: Bool
    var contentSize: String

    /// `iPhone 16 Pro Simulator, iOS 26.0, 393×852pt @3x, light mode, Dynamic Type L`
    var summary: String {
        let size = "\(Rect.number(Double(screenSize.width)))×\(Rect.number(Double(screenSize.height)))pt"
        let mode = isDarkMode ? "dark mode" : "light mode"
        return "\(model), iOS \(systemVersion), \(size) @\(Rect.number(scale))x, \(mode), Dynamic Type \(contentSize)"
    }
}

/// Builds the markdown that gets copied to the clipboard.
enum MarkdownFormatter {

    static func document(_ annotations: [Annotation], appName: String, bundleID: String?, device: DeviceInfo?) -> String {
        var lines: [String] = []
        var title = "# iOS feedback: \(appName)"
        if let bundleID { title += " (\(bundleID))" }
        lines.append(title)
        if let device { lines.append("Device: \(device.summary)") }
        for (index, annotation) in annotations.enumerated() {
            lines.append("")
            lines.append(self.annotation(annotation, number: index + 1))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func annotation(_ a: Annotation, number: Int) -> String {
        var lines: [String] = []
        if let intent = a.intent {
            lines.append("## [\(intent.rawValue)] Annotation \(number)")
        } else {
            lines.append("## Annotation \(number)")
        }
        lines.append("**Screen:** \(code(a.screen))")

        if a.isArea {
            if let box = a.boundingBox { lines.append("**Area:** \(code(box.formatted))") }
            if let tag = a.agentationTag { lines.append("**Inside:** \(code(tag))") }
            if !a.containedTags.isEmpty {
                lines.append("**Contains:** " + a.containedTags.map(code).joined(separator: ", "))
            }
        } else {
            var element = "**Element:** \(code(a.element))"
            if let viewClass = a.viewClass, viewClass != a.element { element += " (\(code(viewClass)))" }
            lines.append(element)
            if let identifier = a.accessibilityIdentifier { lines.append("**Identifier:** \(code(identifier))") }
            if let tag = a.agentationTag { lines.append("**Tag:** \(code(tag))") }
        }
        if let source = a.sourceLocation { lines.append("**Source:** \(code(source))") }
        lines.append("**Path:** \(code(a.elementPath))")
        if !a.viewControllers.isEmpty {
            lines.append("**View controllers:** \(code(a.viewControllers.joined(separator: " > ")))")
        }
        if !a.isArea, let box = a.boundingBox { lines.append("**Frame:** \(code(box.formatted))") }
        if let text = a.text { lines.append("**Text:** \(quote(text))") }
        if let label = a.accessibilityLabel, label != a.text {
            lines.append("**Accessibility label:** \(quote(label))")
        }
        if !a.nearbyText.isEmpty {
            let heading = a.isArea ? "**Text in area:** " : "**Nearby text:** "
            lines.append(heading + a.nearbyText.map(quote).joined(separator: ", "))
        }
        if let style = a.style { lines.append("**Style:** \(code(style))") }
        if let shot = a.screenshotPath { lines.append("**Screenshot:** \(code(shot))") }
        lines.append("**Note:** \(a.comment)")
        return lines.joined(separator: "\n")
    }

    /// Plain-text summary shown in inspect mode.
    static func inspect(_ e: CapturedElement, screen: String) -> String {
        var lines: [String] = []
        var type = "type: \(e.element)"
        if let viewClass = e.viewClass, viewClass != e.element { type += " (\(viewClass))" }
        lines.append(type)
        if let identifier = e.accessibilityIdentifier { lines.append("identifier: \(identifier)") }
        if let tag = e.agentationTag { lines.append("tag: \(tag)") }
        if let source = e.sourceLocation { lines.append("source: \(source)") }
        lines.append("screen: \(screen)")
        lines.append("path: \(e.elementPath)")
        if !e.viewControllers.isEmpty { lines.append("view controllers: \(e.viewControllers.joined(separator: " > "))") }
        lines.append("frame: \(Rect(e.frame).formatted) (pt, window)")
        if let text = e.text { lines.append("text: \(quote(text))") }
        if let label = e.accessibilityLabel, label != e.text { lines.append("accessibility label: \(quote(label))") }
        if !e.nearbyText.isEmpty { lines.append("nearby: " + e.nearbyText.map(quote).joined(separator: ", ")) }
        if let style = e.style { lines.append("style: \(style)") }
        return lines.joined(separator: "\n")
    }

    static func code(_ value: String) -> String {
        "`" + value.replacingOccurrences(of: "`", with: "'") + "`"
    }

    static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\n", with: " ") + "\""
    }
}
