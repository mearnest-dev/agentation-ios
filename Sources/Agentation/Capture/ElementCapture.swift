#if os(iOS)
import UIKit

/// Finds what is under a point (or inside an area) in the app window and collects
/// the details an agent needs to find it in code.
///
/// UIKit views are found by walking the view hierarchy. SwiftUI mostly draws without one
/// `UIView` per view, so inside hosting views the accessibility tree is used instead.
@MainActor
enum ElementCapture {

    struct TextNode {
        let text: String
        let frame: CGRect
    }

    // MARK: - Element at a point

    static func element(at point: CGPoint, in window: UIWindow) -> CapturedElement {
        let resolved = resolve(at: point, in: window)
        let view = resolved.view
        var node = resolved.node
        let nodeFrame = resolved.nodeFrame
        let markers = TagRegistry.markers(containing: point, in: window)
        let viewFrame = view.convert(view.bounds, to: nil)

        let element: String
        let text: String?
        let label: String?
        let identifier: String?
        let frame: CGRect
        let viewClass: String?
        let style: String?

        if let node, let nodeFrame, isUsefulNode(nodeFrame, comparedTo: view) {
            element = elementName(forTraits: node.accessibilityTraits)
            label = node.accessibilityLabel.nonEmpty
            if let value = node.accessibilityValue.nonEmpty {
                text = label.map { "\($0) (value: \(value))" } ?? value
            } else {
                text = label
            }
            identifier = accessibilityIdentifier(of: node) ?? view.accessibilityIdentifier.nonEmpty
            frame = nodeFrame
            viewClass = nil
            style = nil
        } else {
            node = nil
            element = friendlyName(for: view)
            label = view.accessibilityLabel.nonEmpty
            text = visibleText(of: view)
            identifier = view.accessibilityIdentifier.nonEmpty
            frame = viewFrame
            viewClass = className(view)
            style = self.style(of: view)
        }

        var path = viewPath(for: view, in: window)
        path.append(contentsOf: markers.compactMap(\.markerTag))
        if node != nil {
            path.append(text.map { "\(element) \"\(truncate($0, 30))\"" } ?? element)
        }

        return CapturedElement(
            element: element,
            elementPath: path.joined(separator: " > "),
            viewClass: viewClass,
            viewControllers: viewControllers(for: view),
            accessibilityIdentifier: identifier,
            accessibilityLabel: label,
            agentationTag: markers.last(where: { $0.markerTag != nil })?.markerTag ?? taggedAncestor(of: view),
            sourceLocation: markers.last(where: { $0.source != nil })?.source,
            text: text.map { truncate($0, 160) },
            nearbyText: nearbyText(around: frame, excluding: text, in: window),
            style: style,
            frame: frame,
            isArea: false
        )
    }

    /// The view under `point`, plus the SwiftUI accessibility element there when the view is a hosting view.
    private static func resolve(at point: CGPoint, in window: UIWindow) -> (view: UIView, node: NSObject?, nodeFrame: CGRect?) {
        let front = deepestView(at: point, in: window) ?? window
        guard let host = hostingAncestor(of: front) else { return (controlAncestor(of: front) ?? front, nil, nil) }
        let screenPoint = window.convert(point, to: window.screen.coordinateSpace)

        func node(in root: UIView) -> (NSObject, CGRect)? {
            guard let node = accessibilityNode(at: screenPoint, in: root, depth: 0) else { return nil }
            return (node, window.convert(node.accessibilityFrame, from: window.screen.coordinateSpace))
        }

        // An empty hosting view can sit on top of the content: on iOS 26 the floating tab bar
        // container covers the whole screen. Look through it to the content underneath.
        var target = host
        if front === host, accessibilityChildren(of: host).isEmpty,
           let under = hostingViews(at: point, in: window).first(where: {
               !$0.isDescendant(of: host) && !host.isDescendant(of: $0) && !accessibilityChildren(of: $0).isEmpty
           }) {
            target = under
        }
        let view = target === host ? front : (deepestView(at: point, in: target) ?? target)
        let found = node(in: target)
        return (controlAncestor(of: view) ?? view, found?.0, found?.1)
    }

    /// Taps on a control's internals (a button's label, a text field's placeholder) report the control.
    private static func controlAncestor(of view: UIView) -> UIView? {
        var current: UIView? = view
        for _ in 0..<4 {
            guard let v = current else { return nil }
            if v is UIControl { return v }
            current = v.superview
        }
        return nil
    }

    // MARK: - Area

    static func area(_ rect: CGRect, in window: UIWindow) -> CapturedElement {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let container = resolve(at: center, in: window).view
        let enclosing = TagRegistry.markers(enclosing: rect, in: window)
        let inside = unique(TagRegistry.markers(inside: rect, in: window).compactMap(\.markerTag))

        var texts: [TextNode] = []
        for node in textNodes(in: window) {
            let overlap = node.frame.intersection(rect)
            guard !overlap.isNull, area(overlap) >= area(node.frame) * 0.5 else { continue }
            texts.append(node)
        }
        texts.sort { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }

        var path = viewPath(for: container, in: window)
        path.append(contentsOf: enclosing.compactMap(\.markerTag))
        path.append("area")

        return CapturedElement(
            element: "Area",
            elementPath: path.joined(separator: " > "),
            viewClass: nil,
            viewControllers: viewControllers(for: container),
            accessibilityIdentifier: nil,
            accessibilityLabel: nil,
            agentationTag: enclosing.last(where: { $0.markerTag != nil })?.markerTag,
            sourceLocation: enclosing.last(where: { $0.source != nil })?.source,
            text: nil,
            nearbyText: Array(unique(texts.map(\.text)).prefix(8)),
            containedTags: Array(inside.prefix(6)),
            style: nil,
            frame: rect,
            isArea: true
        )
    }

    // MARK: - View hierarchy

    /// The front-most visible view under `point`, preferring views that draw something.
    static func deepestView(at point: CGPoint, in root: UIView) -> UIView? {
        guard isEligible(root), root.bounds.contains(root.convert(point, from: nil)) else { return nil }
        var fallback: UIView?
        for subview in root.subviews.reversed() {
            guard let hit = deepestView(at: point, in: subview) else { continue }
            if isVisual(hit) { return hit }
            if fallback == nil { fallback = hit }
        }
        return fallback ?? root
    }

    private static func isEligible(_ view: UIView) -> Bool {
        !view.isHidden && view.alpha > 0.01 && !(view is AgentationMarkerView)
    }

    private static func isVisual(_ view: UIView) -> Bool {
        if view is UIControl || view is UILabel || view is UIImageView || view is UITextView { return true }
        if isHostingView(view) || view.layer.contents != nil { return true }
        if let background = view.backgroundColor, background.cgColor.alpha > 0.05 { return true }
        return false
    }

    /// Hosting views under `point`, front-most first.
    static func hostingViews(at point: CGPoint, in root: UIView) -> [UIView] {
        var result: [UIView] = []
        func visit(_ view: UIView) {
            guard isEligible(view), view.bounds.contains(view.convert(point, from: nil)) else { return }
            for subview in view.subviews.reversed() { visit(subview) }
            if isHostingView(view) { result.append(view) }
        }
        visit(root)
        return result
    }

    /// An accessibility element is worth reporting when it is smaller than the view that hosts it.
    private static func isUsefulNode(_ nodeFrame: CGRect?, comparedTo view: UIView) -> Bool {
        guard let nodeFrame else { return false }
        let viewArea = area(view.convert(view.bounds, to: nil))
        return area(nodeFrame) > 0 && area(nodeFrame) < viewArea * 0.98
    }

    static func isHostingView(_ view: UIView) -> Bool {
        String(describing: type(of: view)).contains("HostingView")
    }

    private static func hostingAncestor(of view: UIView) -> UIView? {
        var current: UIView? = view
        while let v = current {
            if isHostingView(v) { return v }
            current = v.superview
        }
        return nil
    }

    private static func taggedAncestor(of view: UIView) -> String? {
        var current: UIView? = view
        while let v = current {
            if let tag = v.agentationTag { return tag }
            current = v.superview
        }
        return nil
    }

    private static let noiseClasses: Set<String> = [
        "UITransitionView", "UIDropShadowView", "UILayoutContainerView", "UINavigationTransitionView",
        "UIViewControllerWrapperView", "UITableViewCellContentView", "UIView",
    ]

    /// Condensed path from the window down to `view`, with owning view controllers inlined.
    static func viewPath(for view: UIView, in window: UIWindow) -> [String] {
        var parts: [String] = []
        var current: UIView? = view
        while let v = current, v !== window {
            let ownedByController = v.next is UIViewController
            let skip = v !== view && (isNoise(v) || (isHostingView(v) && ownedByController))
            if !skip { parts.append(pathComponent(for: v)) }
            if let controller = v.next as? UIViewController {
                parts.append(TypeNames.shortTypeName(String(describing: type(of: controller))))
            }
            current = v.superview
        }
        parts.reverse()
        if parts.count > 8 { parts = ["…"] + parts.suffix(8) }
        return parts
    }

    private static func isNoise(_ view: UIView) -> Bool {
        if view.agentationTag != nil || view.accessibilityIdentifier.nonEmpty != nil { return false }
        let name = String(describing: type(of: view))
        return (name.hasPrefix("_") && !isHostingView(view)) || noiseClasses.contains(name)
    }

    private static func pathComponent(for view: UIView) -> String {
        if let tag = view.agentationTag { return tag }
        var name = className(view)
        if let superview = view.superview {
            let siblings = superview.subviews.filter { type(of: $0) == type(of: view) }
            if siblings.count > 1, let index = siblings.firstIndex(where: { $0 === view }) {
                name += "[\(index)]"
            }
        }
        if let identifier = view.accessibilityIdentifier.nonEmpty { name += "#\(identifier)" }
        return name
    }

    private static func viewControllers(for view: UIView) -> [String] {
        var result: [String] = []
        var responder: UIResponder? = view
        while let r = responder {
            if let controller = r as? UIViewController {
                result.append(TypeNames.shortTypeName(String(describing: type(of: controller))))
            }
            responder = r.next
        }
        return result.reversed()
    }

    static func className(_ object: AnyObject) -> String {
        TypeNames.shortTypeName(String(describing: type(of: object)))
    }

    /// `UIButton` → `Button`; custom classes keep their name.
    private static func friendlyName(for view: UIView) -> String {
        let name = className(view)
        if name.hasPrefix("UI"), name.count > 2, name[name.index(name.startIndex, offsetBy: 2)].isUppercase {
            return String(name.dropFirst(2))
        }
        return name
    }

    // MARK: - Accessibility (SwiftUI)

    private static func accessibilityChildren(of object: NSObject) -> [NSObject] {
        if let elements = object.accessibilityElements {
            return elements.compactMap { $0 as? NSObject }
        }
        let count = object.accessibilityElementCount()
        if count != NSNotFound, count > 0, count < 2000 {
            return (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
        }
        // Plain container views (e.g. SwiftUI's HostingScrollView on iOS 26) expose their
        // accessibility elements through subviews, the way UIKit's default traversal does.
        if let view = object as? UIView, !view.isAccessibilityElement {
            return view.subviews.filter { isEligible($0) && !$0.accessibilityElementsHidden }
        }
        return []
    }

    /// Smallest accessibility element under `screenPoint`.
    private static func accessibilityNode(at screenPoint: CGPoint, in root: NSObject, depth: Int) -> NSObject? {
        guard depth < 40 else { return nil }
        var best: NSObject?
        for child in accessibilityChildren(of: root) where !child.accessibilityElementsHidden {
            let frame = child.accessibilityFrame
            if frame == .zero {
                // Some containers report no frame; their children may still match.
                best = smaller(best, accessibilityNode(at: screenPoint, in: child, depth: depth + 1))
                continue
            }
            guard frame.contains(screenPoint) else { continue }
            let deeper = accessibilityNode(at: screenPoint, in: child, depth: depth + 1)
            best = smaller(best, deeper ?? (child.isAccessibilityElement ? child : nil))
        }
        return best
    }

    private static func smaller(_ a: NSObject?, _ b: NSObject?) -> NSObject? {
        guard let a else { return b }
        guard let b else { return a }
        return area(b.accessibilityFrame) < area(a.accessibilityFrame) ? b : a
    }

    private static func accessibilityIdentifier(of object: NSObject) -> String? {
        if let identifier = (object as? UIAccessibilityIdentification)?.accessibilityIdentifier.nonEmpty {
            return identifier
        }
        let selector = NSSelectorFromString("accessibilityIdentifier")
        if object.responds(to: selector),
           let value = object.perform(selector)?.takeUnretainedValue() as? String,
           !value.isEmpty {
            return value
        }
        return nil
    }

    private static func elementName(forTraits traits: UIAccessibilityTraits) -> String {
        if traits.contains(.button) { return "Button" }
        if traits.contains(.link) { return "Link" }
        if traits.contains(.searchField) { return "SearchField" }
        if traits.contains(.adjustable) { return "Slider" }
        if traits.contains(.header) { return "Header" }
        if traits.contains(.image) { return "Image" }
        if traits.contains(.tabBar) { return "TabBar" }
        if traits.contains(.staticText) { return "Text" }
        return "Element"
    }

    private static func flattenAccessibility(_ root: NSObject, limit: Int) -> [NSObject] {
        var result: [NSObject] = []
        var queue: [(NSObject, Int)] = [(root, 0)]
        while !queue.isEmpty, result.count < limit {
            let (object, depth) = queue.removeFirst()
            for child in accessibilityChildren(of: object) where !child.accessibilityElementsHidden {
                if child.isAccessibilityElement { result.append(child) }
                if depth < 30 { queue.append((child, depth + 1)) }
            }
        }
        return result
    }

    // MARK: - Text

    private static func directText(of view: UIView) -> String? {
        switch view {
        case let label as UILabel:
            return label.text.nonEmpty
        case let field as UITextField:
            return field.text.nonEmpty ?? field.placeholder.nonEmpty.map { "placeholder: \($0)" }
        case let textView as UITextView:
            return textView.text.nonEmpty
        default:
            return nil
        }
    }

    static func visibleText(of view: UIView) -> String? {
        if let text = directText(of: view) { return text }
        if let button = view as? UIButton {
            return (button.currentTitle ?? button.configuration?.title ?? button.titleLabel?.text).nonEmpty
        }
        if let segmented = view as? UISegmentedControl, segmented.selectedSegmentIndex != UISegmentedControl.noSegment {
            return segmented.titleForSegment(at: segmented.selectedSegmentIndex)
        }
        if let toggle = view as? UISwitch { return toggle.isOn ? "On" : "Off" }

        // Containers such as table cells: join the labels inside.
        var parts: [String] = []
        collectText(in: view, into: &parts, depth: 0)
        return parts.isEmpty ? nil : truncate(parts.prefix(3).joined(separator: " · "), 160)
    }

    private static func collectText(in view: UIView, into parts: inout [String], depth: Int) {
        guard depth < 12, parts.count < 3 else { return }
        for subview in view.subviews where isEligible(subview) {
            if let text = directText(of: subview) {
                parts.append(text)
            } else {
                collectText(in: subview, into: &parts, depth: depth + 1)
            }
        }
    }

    /// Visible text on screen with frames in window coordinates.
    static func textNodes(in window: UIWindow, limit: Int = 800) -> [TextNode] {
        var result: [TextNode] = []
        func visit(_ view: UIView, depth: Int) {
            guard result.count < limit, depth < 60, isEligible(view) else { return }
            if isHostingView(view) {
                for node in flattenAccessibility(view, limit: 400) where !(node is UIView) {
                    guard let label = node.accessibilityLabel.nonEmpty else { continue }
                    let frame = window.convert(node.accessibilityFrame, from: window.screen.coordinateSpace)
                    if frame.intersects(window.bounds) { result.append(TextNode(text: truncate(label, 80), frame: frame)) }
                }
            }
            if let text = directText(of: view) {
                let frame = view.convert(view.bounds, to: nil)
                if frame.intersects(window.bounds) { result.append(TextNode(text: truncate(text, 80), frame: frame)) }
                return
            }
            for subview in view.subviews { visit(subview, depth: depth + 1) }
        }
        visit(window, depth: 0)
        return result
    }

    private static func nearbyText(around frame: CGRect, excluding ownText: String?, in window: UIWindow) -> [String] {
        let candidates = textNodes(in: window)
            .filter { !frame.contains($0.frame) && $0.text != ownText }
            .map { (text: $0.text, distance: gap(frame, $0.frame)) }
            .filter { $0.distance < 120 }
            .sorted { $0.distance < $1.distance }
        return Array(unique(candidates.map { $0.text }).prefix(4))
    }

    // MARK: - Style

    private static func style(of view: UIView) -> String? {
        var parts: [String] = []
        let traits = view.traitCollection
        if let font = font(of: view) {
            var name = font.fontName
            while name.hasPrefix(".") { name.removeFirst() }
            parts.append("font=\(name) \(Rect.number(Double(font.pointSize)))pt")
        }
        if let color = foregroundColor(of: view) { parts.append("foreground=\(hex(color, traits))") }
        if let background = backgroundColor(of: view) { parts.append("background=\(hex(background, traits))") }
        if view.layer.cornerRadius > 0 { parts.append("cornerRadius=\(Rect.number(Double(view.layer.cornerRadius)))") }
        if view.layer.borderWidth > 0, let border = view.layer.borderColor {
            parts.append("border=\(Rect.number(Double(view.layer.borderWidth)))pt \(hex(UIColor(cgColor: border), traits))")
        }
        if view.alpha < 1 { parts.append("alpha=\(Rect.number(Double(view.alpha)))") }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    private static func font(of view: UIView) -> UIFont? {
        switch view {
        case let label as UILabel: return label.font
        case let button as UIButton: return button.titleLabel?.font
        case let field as UITextField: return field.font
        case let textView as UITextView: return textView.font
        default: return nil
        }
    }

    private static func foregroundColor(of view: UIView) -> UIColor? {
        switch view {
        case let label as UILabel: return label.textColor
        case let button as UIButton: return button.configuration?.baseForegroundColor ?? button.currentTitleColor
        case let field as UITextField: return field.textColor
        case let textView as UITextView: return textView.textColor
        default: return nil
        }
    }

    private static func backgroundColor(of view: UIView) -> UIColor? {
        if let button = view as? UIButton, let color = button.configuration?.background.backgroundColor {
            return color
        }
        if let color = view.backgroundColor, color.cgColor.alpha > 0.01 { return color }
        return nil
    }

    private static func hex(_ color: UIColor, _ traits: UITraitCollection) -> String {
        let resolved = color.resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return resolved.description }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        let value = String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
        return a < 0.999 ? value + String(format: " @%.0f%%", a * 100) : value
    }

    // MARK: - Geometry helpers

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }

    /// Distance between the edges of two rects (0 when they overlap).
    private static func gap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = max(0, max(a.minX - b.maxX, b.minX - a.maxX))
        let dy = max(0, max(a.minY - b.maxY, b.minY - a.maxY))
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
#endif
