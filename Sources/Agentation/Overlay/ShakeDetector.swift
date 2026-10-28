#if os(iOS)
import UIKit
import ObjectiveC

extension Notification.Name {
    static let agentationShake = Notification.Name("AgentationShake")
}

/// Posts `.agentationShake` when the device is shaken (Device → Shake, ⌃⌘Z in the Simulator).
///
/// Shake events travel up the responder chain to the window, so `UIWindow.motionEnded`
/// is swizzled once. Debug builds only.
enum ShakeDetector {
    private static var installed = false

    @MainActor
    static func install() {
        guard !installed else { return }
        installed = true

        let windowClass: AnyClass = UIWindow.self
        let originalSelector = #selector(UIResponder.motionEnded(_:with:))
        let swizzledSelector = #selector(UIWindow.agentation_motionEnded(_:with:))
        guard let originalMethod = class_getInstanceMethod(windowClass, originalSelector),
              let swizzledMethod = class_getInstanceMethod(windowClass, swizzledSelector) else { return }

        // UIWindow may inherit motionEnded from UIResponder. Add it to UIWindow first so
        // the exchange doesn't affect every responder.
        if class_addMethod(windowClass, originalSelector,
                           method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod)) {
            class_replaceMethod(windowClass, swizzledSelector,
                                method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
}

extension UIWindow {
    @objc func agentation_motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .agentationShake, object: nil)
        }
        // After swizzling, this calls the original implementation.
        agentation_motionEnded(motion, with: event)
    }
}
#endif
