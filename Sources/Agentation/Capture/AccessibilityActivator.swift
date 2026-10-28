#if os(iOS)
import Foundation

/// SwiftUI only builds its accessibility tree when something asks for it (VoiceOver, UI tests).
/// Capture reads SwiftUI views through that tree, so Agentation turns on the same
/// automation mode UI tests use. Debug builds only; `Agentation.start` is compiled out of release.
enum AccessibilityActivator {
    private typealias SetEnabled = @convention(c) (Int32) -> Void
    private typealias IsEnabled = @convention(c) () -> Int32
    private static var enabledByUs = false

    static func enable() {
        #if DEBUG
        guard let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let setSymbol = dlsym(handle, "_AXSSetAutomationEnabled"),
              let getSymbol = dlsym(handle, "_AXSAutomationEnabled") else {
            print("[Agentation] Could not enable accessibility; SwiftUI views may be captured less precisely.")
            return
        }
        let isEnabled = unsafeBitCast(getSymbol, to: IsEnabled.self)
        guard isEnabled() == 0 else { return }
        unsafeBitCast(setSymbol, to: SetEnabled.self)(1)
        enabledByUs = true
        #endif
    }

    /// Turns the mode back off if `enable()` turned it on.
    static func restore() {
        #if DEBUG
        guard enabledByUs,
              let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let setSymbol = dlsym(handle, "_AXSSetAutomationEnabled") else { return }
        unsafeBitCast(setSymbol, to: SetEnabled.self)(0)
        enabledByUs = false
        #endif
    }
}
#endif
