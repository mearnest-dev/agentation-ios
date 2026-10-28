import Foundation

/// Turns runtime type names into short names that are worth grepping for.
///
/// SwiftUI hosting types look like
/// `UIHostingController<ModifiedContent<CheckoutView, _EnvironmentKeyWritingModifier<…>>>`.
/// The interesting part is `CheckoutView`.
enum TypeNames {
    private static let wrapperTypes: Set<String> = ["ModifiedContent", "Optional", "_ConditionalContent"]
    private static let uninformativeRoots: Set<String> = ["AnyView", "EmptyView", "AnyHashable"]

    /// Splits `Base<A, B<C>>` into `Base` and `["A", "B<C>"]`.
    static func genericArguments(of typeName: String) -> (base: String, args: [String])? {
        guard let open = typeName.firstIndex(of: "<"), typeName.last == ">" else { return nil }
        let base = String(typeName[..<open])
        let inner = typeName[typeName.index(after: open)..<typeName.index(before: typeName.endIndex)]
        var args: [String] = []
        var depth = 0
        var current = ""
        for character in inner {
            switch character {
            case "<", "(", "[":
                depth += 1
                current.append(character)
            case ">", ")", "]":
                depth -= 1
                current.append(character)
            case "," where depth == 0:
                args.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default:
                current.append(character)
            }
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { args.append(last) }
        return (base, args)
    }

    /// The root SwiftUI view of a hosting controller or hosting view type name, or nil for other types.
    static func hostedRootName(_ typeName: String) -> String? {
        guard let parsed = genericArguments(of: typeName),
              parsed.base.hasSuffix("HostingController") || parsed.base.hasSuffix("HostingView"),
              var root = parsed.args.first else { return nil }
        while let wrapped = genericArguments(of: root),
              wrapperTypes.contains(stripModule(wrapped.base)),
              let first = wrapped.args.first {
            root = first
        }
        return stripModule(root)
    }

    /// True when a hosted root name says nothing about the screen (e.g. `AnyView`).
    static func isUninformative(_ rootName: String) -> Bool {
        let base = genericArguments(of: rootName)?.base ?? rootName
        return uninformativeRoots.contains(base) || base.hasPrefix("_")
    }

    /// Short display name for any view or view controller type.
    static func shortTypeName(_ typeName: String) -> String {
        if let root = hostedRootName(typeName), let base = genericArguments(of: typeName)?.base {
            var cleanBase = stripModule(base)
            while cleanBase.hasPrefix("_") { cleanBase.removeFirst() }
            return "\(cleanBase)<\(root)>"
        }
        let stripped = stripModule(typeName)
        if stripped.count > 60, let base = genericArguments(of: stripped)?.base {
            return "\(base)<…>"
        }
        return stripped
    }

    /// `SwiftUI.AnyView` → `AnyView`. Only looks at the part before any generic arguments.
    static func stripModule(_ typeName: String) -> String {
        let head: Substring
        let tail: Substring
        if let open = typeName.firstIndex(of: "<") {
            head = typeName[..<open]
            tail = typeName[open...]
        } else {
            head = typeName[...]
            tail = ""
        }
        if let dot = head.lastIndex(of: ".") {
            return String(head[head.index(after: dot)...]) + tail
        }
        return typeName
    }
}
