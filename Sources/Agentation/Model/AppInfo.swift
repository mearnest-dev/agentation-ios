import Foundation

/// Identity of the host app, used in copied output and sync URLs.
enum AppInfo {
    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "unknown.app"
    }

    static var displayName: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? "App"
    }

    static var scheme: String {
        #if targetEnvironment(simulator)
        return "ios-sim"
        #else
        return "ios"
        #endif
    }

    /// One agentation-mcp session per app: `ios-sim://com.example.app`
    static var sessionURL: String { "\(scheme)://\(bundleID)" }

    /// `ios-sim://com.example.app/CheckoutView`
    static func url(for screen: String) -> String {
        let path = screen.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "screen"
        return "\(sessionURL)/\(path)"
    }
}
