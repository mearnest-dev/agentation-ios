#if os(iOS)
import UIKit

/// Where the toolbar starts. It can be dragged anywhere afterwards.
public enum ToolbarPosition: Sendable {
    case bottomTrailing, bottomLeading, topTrailing, topLeading
}

/// Options for `Agentation.start(...)` and the `.agentation(...)` SwiftUI modifier.
public struct Configuration {
    /// agentation-mcp server URL, e.g. `http://localhost:4747`. `nil` keeps feedback local (copy only).
    public var endpoint: String?
    /// Name shown at the top of copied feedback. Defaults to the bundle display name.
    public var appName: String?
    /// Save a cropped PNG for each annotation.
    public var captureScreenshots: Bool
    public var toolbarPosition: ToolbarPosition
    /// Single-key shortcuts (I, A, C, Esc) while the toolbar is open.
    public var enableKeyCommands: Bool
    /// Run on a physical device. Off by default; the Simulator always works.
    public var allowOnDevice: Bool
    public var onAnnotationAdd: ((Annotation) -> Void)?
    public var onCopy: ((String) -> Void)?

    public init(
        endpoint: String? = nil,
        appName: String? = nil,
        captureScreenshots: Bool = true,
        toolbarPosition: ToolbarPosition = .bottomTrailing,
        enableKeyCommands: Bool = true,
        allowOnDevice: Bool = false,
        onAnnotationAdd: ((Annotation) -> Void)? = nil,
        onCopy: ((String) -> Void)? = nil
    ) {
        self.endpoint = endpoint
        self.appName = appName
        self.captureScreenshots = captureScreenshots
        self.toolbarPosition = toolbarPosition
        self.enableKeyCommands = enableKeyCommands
        self.allowOnDevice = allowOnDevice
        self.onAnnotationAdd = onAnnotationAdd
        self.onCopy = onCopy
    }
}

/// Visual feedback for AI coding agents, for iOS apps.
///
/// ```swift
/// Agentation.start(endpoint: "http://localhost:4747")
/// ```
///
/// Only runs in `DEBUG` builds, and only in the Simulator unless `allowOnDevice` is set.
@MainActor
public enum Agentation {
    private static var window: UIWindow?
    private static var controller: OverlayViewController?
    private static var pendingConfiguration: Configuration?
    private static var sceneObserver: NSObjectProtocol?

    public static var isRunning: Bool { window != nil }

    /// All saved annotations, across screens.
    public static var annotations: [Annotation] { controller?.allAnnotations ?? [] }

    public static func start(
        endpoint: String? = nil,
        appName: String? = nil,
        captureScreenshots: Bool = true,
        toolbarPosition: ToolbarPosition = .bottomTrailing,
        enableKeyCommands: Bool = true,
        allowOnDevice: Bool = false,
        onAnnotationAdd: ((Annotation) -> Void)? = nil,
        onCopy: ((String) -> Void)? = nil
    ) {
        start(Configuration(
            endpoint: endpoint, appName: appName, captureScreenshots: captureScreenshots,
            toolbarPosition: toolbarPosition, enableKeyCommands: enableKeyCommands,
            allowOnDevice: allowOnDevice, onAnnotationAdd: onAnnotationAdd, onCopy: onCopy))
    }

    public static func start(_ configuration: Configuration) {
        #if DEBUG
        guard window == nil, pendingConfiguration == nil else { return }
        #if !targetEnvironment(simulator)
        guard configuration.allowOnDevice else {
            print("[Agentation] Not started on a physical device. Pass allowOnDevice: true to enable it.")
            return
        }
        #endif
        if let scene = findScene() {
            install(configuration, in: scene)
        } else {
            pendingConfiguration = configuration
            observeSceneActivation()
        }
        #else
        _ = configuration
        #endif
    }

    /// Removes the toolbar. Saved annotations are kept.
    public static func stop() {
        pendingConfiguration = nil
        if let observer = sceneObserver {
            NotificationCenter.default.removeObserver(observer)
            sceneObserver = nil
        }
        controller?.setExpanded(false)
        window?.isHidden = true
        window = nil
        controller = nil
        AccessibilityActivator.restore()
    }

    /// Opens the toolbar.
    public static func show() {
        controller?.setExpanded(true)
    }

    /// Copies all annotations as markdown, as if the Copy button was tapped.
    public static func copyAll() {
        controller?.copyAll()
    }

    private static func findScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    private static func observeSceneActivation() {
        guard sceneObserver == nil else { return }
        sceneObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                guard let configuration = pendingConfiguration, let scene = findScene() else { return }
                pendingConfiguration = nil
                if let observer = sceneObserver {
                    NotificationCenter.default.removeObserver(observer)
                    sceneObserver = nil
                }
                install(configuration, in: scene)
            }
        }
    }

    private static func install(_ configuration: Configuration, in scene: UIWindowScene) {
        let overlay = PassthroughWindow(windowScene: scene)
        overlay.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        overlay.backgroundColor = .clear
        let root = OverlayViewController(configuration: configuration)
        root.overlayWindow = overlay
        overlay.rootViewController = root
        // Visible but not key, so the app keeps keyboard focus.
        overlay.isHidden = false
        window = overlay
        controller = root
        ShakeDetector.install()
        AccessibilityActivator.enable()
    }
}
#endif
