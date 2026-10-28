#if os(iOS)
import UIKit

/// Invisible view placed behind a SwiftUI view by `.agentationTag(_:)` / `.agentationSource()`.
/// Its frame matches the tagged view, which lets a tap point be mapped back to a tag.
final class AgentationMarkerView: UIView {
    var markerTag: String?
    var source: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { TagRegistry.register(self) }
    }
}

@MainActor
enum TagRegistry {
    private static let views = NSHashTable<AgentationMarkerView>.weakObjects()

    static func register(_ view: AgentationMarkerView) {
        views.add(view)
    }

    /// Visible markers in `window` with their frames in window coordinates.
    static func visibleMarkers(in window: UIWindow) -> [(view: AgentationMarkerView, frame: CGRect)] {
        views.allObjects.compactMap { view in
            guard view.window === window, isVisible(view) else { return nil }
            let frame = view.convert(view.bounds, to: nil)
            guard frame.width > 0, frame.height > 0 else { return nil }
            return (view, frame)
        }
    }

    /// Markers whose frame contains `point`, outermost (largest) first.
    static func markers(containing point: CGPoint, in window: UIWindow) -> [AgentationMarkerView] {
        visibleMarkers(in: window)
            .filter { $0.frame.contains(point) }
            .sorted { area($0.frame) > area($1.frame) }
            .map { $0.view }
    }

    /// Markers whose frame contains all of `rect`, outermost first.
    static func markers(enclosing rect: CGRect, in window: UIWindow) -> [AgentationMarkerView] {
        visibleMarkers(in: window)
            .filter { $0.frame.contains(rect) }
            .sorted { area($0.frame) > area($1.frame) }
            .map { $0.view }
    }

    /// Markers that sit entirely inside `rect`, in reading order.
    static func markers(inside rect: CGRect, in window: UIWindow) -> [AgentationMarkerView] {
        visibleMarkers(in: window)
            .filter { rect.contains($0.frame) }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
            .map { $0.view }
    }

    private static func isVisible(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let v = current {
            if v.isHidden || v.alpha < 0.01 { return false }
            current = v.superview
        }
        return true
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }
}

private enum AssociatedKeys {
    static var tag: UInt8 = 0
}

public extension UIView {
    /// A name for this view that shows up in annotations and view paths. Use it on UIKit views
    /// the same way `.agentationTag(_:)` is used on SwiftUI views.
    var agentationTag: String? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.tag) as? String }
        set { objc_setAssociatedObject(self, &AssociatedKeys.tag, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    }
}
#endif
