import Foundation

/// Talks to the agentation-mcp HTTP server (`npx agentation-mcp server`, default port 4747).
///
/// Uses the same routes as the web toolbar:
/// `POST /sessions`, `POST /sessions/:id/annotations`, `PATCH|DELETE /annotations/:id`, `GET /sessions/:id`.
final class SyncClient {
    struct HTTPError: Error, CustomStringConvertible {
        let status: Int
        var description: String { "HTTP \(status)" }
    }

    let endpoint: URL
    let sessionURL: String
    private let urlSession: URLSession
    private let defaults: UserDefaults
    private let defaultsKey: String
    private(set) var sessionId: String?

    init?(endpoint: String, sessionURL: String, urlSession: URLSession = .shared, defaults: UserDefaults = .standard) {
        var trimmed = endpoint.trimmingCharacters(in: .whitespaces)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" else { return nil }
        self.endpoint = url
        self.sessionURL = sessionURL
        self.urlSession = urlSession
        self.defaults = defaults
        self.defaultsKey = "agentation.session.\(url.absoluteString).\(sessionURL)"
        self.sessionId = defaults.string(forKey: defaultsKey)
    }

    /// Returns the cached session ID or creates a new session.
    func ensureSession() async throws -> String {
        if let sessionId { return sessionId }
        struct Body: Encodable { let url: String }
        struct Session: Decodable { let id: String }
        let data = try await send("POST", "sessions", json: try JSONEncoder().encode(Body(url: sessionURL)), expect: [200, 201])
        let id = try JSONDecoder().decode(Session.self, from: data).id
        sessionId = id
        defaults.set(id, forKey: defaultsKey)
        return id
    }

    /// Sends a new annotation and returns the server's ID for it.
    func create(_ annotation: Annotation) async throws -> String {
        let body = try JSONEncoder().encode(ServerAnnotationPayload(annotation))
        do {
            return try await createOnce(body)
        } catch let error as HTTPError where error.status == 404 {
            // The server restarted with a fresh store; start a new session and retry once.
            resetSession()
            return try await createOnce(body)
        }
    }

    func update(serverId: String, with annotation: Annotation) async throws {
        struct Patch: Encodable {
            let comment: String
            let intent: String?
            let attributes: [String: String]
        }
        let patch = Patch(
            comment: annotation.comment,
            intent: ServerAnnotationPayload.serverIntent(annotation.intent),
            attributes: ServerAnnotationPayload.attributes(for: annotation))
        _ = try await send("PATCH", "annotations/\(serverId)", json: try JSONEncoder().encode(patch), expect: [200])
    }

    func delete(serverId: String) async throws {
        _ = try await send("DELETE", "annotations/\(serverId)", json: nil, expect: [200, 204, 404])
    }

    /// Server annotation ID → status (`pending`, `acknowledged`, `resolved`, `dismissed`).
    func fetchStatuses() async throws -> [String: String] {
        struct Session: Decodable {
            struct Item: Decodable {
                let id: String
                let status: String?
            }
            let annotations: [Item]?
        }
        let id = try await ensureSession()
        do {
            let data = try await send("GET", "sessions/\(id)", json: nil, expect: [200])
            let session = try JSONDecoder().decode(Session.self, from: data)
            var result: [String: String] = [:]
            for item in session.annotations ?? [] { result[item.id] = item.status ?? "pending" }
            return result
        } catch let error as HTTPError where error.status == 404 {
            resetSession()
            return [:]
        }
    }

    private func createOnce(_ body: Data) async throws -> String {
        struct Created: Decodable { let id: String }
        let id = try await ensureSession()
        let data = try await send("POST", "sessions/\(id)/annotations", json: body, expect: [200, 201])
        return try JSONDecoder().decode(Created.self, from: data).id
    }

    private func resetSession() {
        sessionId = nil
        defaults.removeObject(forKey: defaultsKey)
    }

    private func send(_ method: String, _ path: String, json: Data?, expect: Set<Int>) async throws -> Data {
        var request = URLRequest(url: endpoint.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 5
        if let json {
            request.httpBody = json
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard expect.contains(status) else { throw HTTPError(status: status) }
        return data
    }
}

/// The annotation shape agentation-mcp expects (see agentation's `Annotation` type).
/// iOS-only details go in `attributes` so agents still see them.
struct ServerAnnotationPayload: Encodable {
    let id: String
    let comment: String
    let element: String
    let elementPath: String
    let x: Double
    let y: Double
    /// Milliseconds, like `Date.now()` on the web.
    let timestamp: Double
    let url: String
    let boundingBox: Rect?
    let nearbyText: String?
    let computedStyles: String?
    let fullPath: String?
    let accessibility: String?
    let sourceFile: String?
    let attributes: [String: String]
    let isMultiSelect: Bool?
    let intent: String?
    let kind: String

    init(_ a: Annotation) {
        id = a.id
        comment = a.comment
        element = a.element
        elementPath = a.elementPath.isEmpty ? a.element : a.elementPath
        x = a.x
        y = a.y
        timestamp = (a.timestamp * 1000).rounded()
        url = a.url
        boundingBox = a.boundingBox
        nearbyText = a.nearbyText.isEmpty ? nil : a.nearbyText.joined(separator: " | ")
        computedStyles = a.style
        fullPath = a.viewControllers.isEmpty ? nil : (a.viewControllers + [a.elementPath]).joined(separator: " > ")
        var accessibilityParts: [String] = []
        if let identifier = a.accessibilityIdentifier { accessibilityParts.append("identifier: \(identifier)") }
        if let label = a.accessibilityLabel { accessibilityParts.append("label: \(label)") }
        accessibility = accessibilityParts.isEmpty ? nil : accessibilityParts.joined(separator: "; ")
        sourceFile = a.sourceLocation
        attributes = Self.attributes(for: a)
        isMultiSelect = a.isArea ? true : nil
        intent = Self.serverIntent(a.intent)
        kind = "feedback"
    }

    /// agentation-mcp knows `fix | change | question | approve`; the original tag is kept in `attributes.category`.
    static func serverIntent(_ intent: Intent?) -> String? {
        guard let intent else { return nil }
        return intent == .bug ? "fix" : "change"
    }

    static func attributes(for a: Annotation) -> [String: String] {
        var result: [String: String] = ["platform": "ios", "screen": a.screen]
        if let value = a.viewClass { result["viewClass"] = value }
        if let value = a.accessibilityIdentifier { result["accessibilityIdentifier"] = value }
        if let value = a.agentationTag { result["agentationTag"] = value }
        if let value = a.screenshotPath { result["screenshotPath"] = value }
        if let value = a.text { result["text"] = value }
        if let value = a.intent { result["category"] = value.rawValue }
        return result
    }
}
