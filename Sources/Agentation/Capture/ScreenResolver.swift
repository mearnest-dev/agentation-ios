#if os(iOS)
import UIKit

/// Works out which screen is showing, so annotations can be grouped per screen.
@MainActor
enum ScreenResolver {

    static func topViewController(in window: UIWindow) -> UIViewController? {
        guard var current = window.rootViewController else { return nil }
        for _ in 0..<32 {
            if let presented = current.presentedViewController, !presented.isBeingDismissed {
                current = presented
            } else if let nav = current as? UINavigationController, let top = nav.topViewController {
                current = top
            } else if let tab = current as? UITabBarController, let selected = tab.selectedViewController {
                current = selected
            } else if let split = current as? UISplitViewController, let last = split.viewControllers.last {
                current = last
            } else if let child = dominantChild(of: current, in: window) {
                current = child
            } else {
                break
            }
        }
        return current
    }

    static func screenName(in window: UIWindow) -> String {
        topViewController(in: window).map(screenName(for:)) ?? "Unknown screen"
    }

    static func screenName(for viewController: UIViewController) -> String {
        let typeName = String(describing: type(of: viewController))
        let title = (viewController.navigationItem.title ?? viewController.title).nonEmpty
        if let root = TypeNames.hostedRootName(typeName) {
            if !TypeNames.isUninformative(root) { return root }
            if let title { return title }
            return TypeNames.shortTypeName(typeName)
        }
        return TypeNames.shortTypeName(typeName)
    }

    /// A child view controller that covers most of the window, e.g. the navigation
    /// controller SwiftUI's `NavigationStack` embeds inside a hosting controller.
    private static func dominantChild(of viewController: UIViewController, in window: UIWindow) -> UIViewController? {
        let windowArea = window.bounds.width * window.bounds.height
        guard windowArea > 0 else { return nil }
        let candidates = viewController.children.compactMap { child -> (UIViewController, CGFloat)? in
            guard child.isViewLoaded, let view = child.view, view.window === window, !view.isHidden, view.alpha > 0.01 else {
                return nil
            }
            let visible = view.convert(view.bounds, to: nil).intersection(window.bounds)
            guard !visible.isNull else { return nil }
            return (child, visible.width * visible.height)
        }
        guard let best = candidates.max(by: { $0.1 < $1.1 }), best.1 >= windowArea * 0.4 else { return nil }
        return best.0
    }
}
#endif
