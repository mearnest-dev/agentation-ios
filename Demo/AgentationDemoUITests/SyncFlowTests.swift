import XCTest

/// Round trip with a real agentation-mcp server. Skipped when none is running.
///
///   npx -y agentation-mcp server   # listens on localhost:4747
final class SyncFlowTests: XCTestCase {
    private let server = URL(string: "http://localhost:4747")!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard (try? request("GET", "health")) != nil else {
            throw XCTSkip("agentation-mcp is not running on localhost:4747")
        }
        app = XCUIApplication()
        app.launch()
    }

    func testCreateEditResolve() throws {
        let started = Date().addingTimeInterval(-1)
        XCTAssertTrue(app.buttons["checkout.payButton"].waitForExistence(timeout: 10))
        app.buttons["Show Agentation"].tap()
        clearAll()

        // Create in the app; the server should receive it.
        let note = "sync test \(UUID().uuidString.prefix(6))"
        app.buttons["Annotate"].tap()
        let pay = app.buttons["checkout.payButton"].frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: pay.midX, dy: pay.midY)).tap()
        let editor = app.textViews["Note"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText(note)
        app.segmentedControls.buttons["Bug"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Annotation 1"].waitForExistence(timeout: 3))

        let created = try XCTUnwrap(waitForServerAnnotation { ($0["comment"] as? String) == note })
        let serverId = try XCTUnwrap(created["id"] as? String)
        XCTAssertEqual(created["intent"] as? String, "fix")
        let attributes = created["attributes"] as? [String: Any]
        XCTAssertEqual(attributes?["accessibilityIdentifier"] as? String, "checkout.payButton")
        XCTAssertEqual(attributes?["category"] as? String, "bug")

        // Edit in the app; the server should get the new comment.
        app.buttons["Annotation 1"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText(" edited")
        app.buttons["Save"].tap()
        XCTAssertNotNil(waitForServerAnnotation { ($0["id"] as? String) == serverId && ($0["comment"] as? String) == note + " edited" })

        // The agent resolves it; the app should drop it.
        let body = try JSONSerialization.data(withJSONObject: ["status": "resolved"])
        _ = try request("PATCH", "annotations/\(serverId)", body: body)
        XCTAssertTrue(app.staticTexts["1 annotation resolved by your agent"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Annotation 1"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.buttons["Copy annotations"].value as? String, "0 annotations")

        // Uploads and polls that start together must share one session.
        let sessions = try XCTUnwrap(json(request("GET", "sessions")) as? [[String: Any]])
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ours = sessions.filter { session in
            guard (session["url"] as? String)?.hasPrefix("ios-sim://dev.mearnest.AgentationDemo") == true,
                  let created = (session["createdAt"] as? String).flatMap(dates.date(from:)) else { return false }
            return created >= started
        }
        XCTAssertLessThanOrEqual(ours.count, 1, "Expected at most one new session, got \(ours.count)")
    }

    // MARK: - Helpers

    private func clearAll() {
        XCTAssertTrue(app.buttons["Clear annotations"].waitForExistence(timeout: 3))
        guard app.buttons["Copy annotations"].value as? String != "0 annotations" else { return }
        app.buttons["Clear annotations"].tap()
        let all = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'All screens'")).firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 3))
        all.tap()
    }

    /// Polls the demo app's session on the server until an annotation matches.
    private func waitForServerAnnotation(timeout: TimeInterval = 10, _ match: ([String: Any]) -> Bool) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let sessions = try? json(request("GET", "sessions")) as? [[String: Any]] {
                for session in sessions where (session["url"] as? String)?.hasPrefix("ios-sim://dev.mearnest.AgentationDemo") == true {
                    guard let id = session["id"] as? String,
                          let detail = try? json(request("GET", "sessions/\(id)")) as? [String: Any],
                          let annotations = detail["annotations"] as? [[String: Any]] else { continue }
                    if let found = annotations.first(where: match) { return found }
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    private func json(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }

    private func request(_ method: String, _ path: String, body: Data? = nil) throws -> Data {
        var request = URLRequest(url: server.appendingPathComponent(path), timeoutInterval: 3)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        var result: Result<Data, Error> = .failure(URLError(.timedOut))
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) {
                result = .success(data ?? Data())
            } else {
                result = .failure(URLError(.badServerResponse))
            }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 5)
        return try result.get()
    }
}
