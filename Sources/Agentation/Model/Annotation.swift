import Foundation
import CoreGraphics

/// A rectangle in points, in the app window's coordinate space.
public struct Rect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(x: Double(rect.origin.x), y: Double(rect.origin.y),
                  width: Double(rect.size.width), height: Double(rect.size.height))
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    /// `x=16 y=712 w=361 h=50`
    var formatted: String {
        "x=\(Rect.number(x)) y=\(Rect.number(y)) w=\(Rect.number(width)) h=\(Rect.number(height))"
    }

    /// Rounds to one decimal place and drops a trailing `.0`.
    static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded(), abs(rounded) < 1e9 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}

/// What kind of change an annotation asks for.
public enum Intent: String, Codable, CaseIterable, Sendable {
    case bug, style, feature, content

    var label: String { rawValue.capitalized }
}

/// One piece of feedback attached to a view or an area of a screen.
public struct Annotation: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var comment: String
    public var intent: Intent?
    /// Seconds since 1970.
    public var timestamp: TimeInterval

    /// Name of the screen (top view controller or SwiftUI root view).
    public var screen: String
    /// Friendly element name, e.g. `Button`, `Text`, `Area`.
    public var element: String
    /// Condensed view path, e.g. `UIHostingController<CheckoutView> > PaymentCard > Button "Pay"`.
    public var elementPath: String
    /// UIKit class of the selected view, when the selection is a UIView.
    public var viewClass: String?
    /// View controllers that own the selected view, outermost first.
    public var viewControllers: [String]
    public var accessibilityIdentifier: String?
    public var accessibilityLabel: String?
    /// Innermost `agentationTag` around the selection.
    public var agentationTag: String?
    /// Innermost `.agentationSource()` around the selection, e.g. `MyApp/CheckoutView.swift:42`.
    public var sourceLocation: String?
    public var text: String?
    /// For element annotations: text close to the element. For area annotations: text inside the area.
    public var nearbyText: [String]
    /// For area annotations: tags of components fully inside the area.
    public var containedTags: [String]
    public var style: String?
    public var boundingBox: Rect?
    /// Marker position, % of window width (0–100).
    public var x: Double
    /// Marker position, points from the top of the window.
    public var y: Double
    public var isArea: Bool
    public var screenshotPath: String?
    /// `ios-sim://<bundle id>/<screen>`
    public var url: String
    /// ID assigned by agentation-mcp after a successful sync.
    public var serverId: String?
}

/// Everything captured about a tapped view or a dragged area, before the user writes a note.
struct CapturedElement: Equatable {
    var element: String
    var elementPath: String
    var viewClass: String?
    var viewControllers: [String] = []
    var accessibilityIdentifier: String?
    var accessibilityLabel: String?
    var agentationTag: String?
    var sourceLocation: String?
    var text: String?
    var nearbyText: [String] = []
    var containedTags: [String] = []
    var style: String?
    /// Window coordinates.
    var frame: CGRect
    var isArea: Bool = false
}

extension Annotation {
    init(
        id: String = UUID().uuidString,
        captured: CapturedElement,
        comment: String,
        intent: Intent?,
        screen: String,
        anchor: CGPoint,
        windowSize: CGSize,
        screenshotPath: String?,
        url: String,
        date: Date = Date()
    ) {
        let width = max(Double(windowSize.width), 1)
        self.init(
            id: id,
            comment: comment,
            intent: intent,
            timestamp: date.timeIntervalSince1970,
            screen: screen,
            element: captured.element,
            elementPath: captured.elementPath.isEmpty ? captured.element : captured.elementPath,
            viewClass: captured.viewClass,
            viewControllers: captured.viewControllers,
            accessibilityIdentifier: captured.accessibilityIdentifier,
            accessibilityLabel: captured.accessibilityLabel,
            agentationTag: captured.agentationTag,
            sourceLocation: captured.sourceLocation,
            text: captured.text,
            nearbyText: captured.nearbyText,
            containedTags: captured.containedTags,
            style: captured.style,
            boundingBox: Rect(captured.frame),
            x: Double(anchor.x) / width * 100,
            y: Double(anchor.y),
            isArea: captured.isArea,
            screenshotPath: screenshotPath,
            url: url,
            serverId: nil
        )
    }
}

extension Optional where Wrapped == String {
    /// The string, or nil when it is nil or empty after trimming.
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

func truncate(_ text: String, _ limit: Int) -> String {
    let single = text.replacingOccurrences(of: "\n", with: " ")
    guard single.count > limit else { return single }
    return String(single.prefix(limit - 1)) + "…"
}
