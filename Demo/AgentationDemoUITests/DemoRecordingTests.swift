import XCTest

/// A slow, scripted walkthrough for recording a demo video. Skipped unless DEMO_EVENTS is set.
/// Run it through `Demo/scripts/record-demo.sh`, which records the Simulator and adds tap circles.
final class DemoRecordingTests: XCTestCase {
    private var app: XCUIApplication!
    private var events: [[String: Double]] = []
    private var eventsPath: String!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["DEMO_EVENTS"] else {
            throw XCTSkip("Set TEST_RUNNER_DEMO_EVENTS to record the demo")
        }
        eventsPath = path
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() {
        if let eventsPath, let data = try? JSONSerialization.data(withJSONObject: events) {
            try? data.write(to: URL(fileURLWithPath: eventsPath))
        }
    }

    func testRecordDemo() {
        XCTAssertTrue(app.buttons["checkout.payButton"].waitForExistence(timeout: 10))
        pause(1.5)

        // Open the toolbar.
        tap(app.buttons["Show Agentation"])
        pause(1.2)

        // Inspect the pay button.
        tap(app.buttons["Inspect"])
        pause(0.8)
        let pay = app.buttons["checkout.payButton"].frame
        tap(at: CGPoint(x: pay.midX, y: pay.midY))
        pause(3.5)
        tap(app.buttons["Close"])
        pause(0.8)

        // Annotate the pay button.
        tap(app.buttons["Annotate"])
        pause(0.8)
        tap(at: CGPoint(x: pay.midX - 60, y: pay.midY))
        write("Corners should be 12 to match the cards", intent: "Style")

        // Annotate the gift note field.
        let gift = app.textFields["checkout.giftNote"].frame
        tap(at: CGPoint(x: gift.midX, y: gift.midY))
        write("Placeholder is too vague", intent: "Content")

        // Drag to annotate an area.
        let window = app.windows.firstMatch.frame
        let start = CGPoint(x: window.minX + 24, y: window.minY + 192)
        let end = CGPoint(x: window.maxX - 24, y: window.minY + 330)
        log(start, kind: 1)
        coordinate(start).press(forDuration: 0.1, thenDragTo: coordinate(end), withVelocity: 350, thenHoldForDuration: 0.3)
        log(end, kind: 2)
        write("More breathing room between rows", intent: "Bug")

        // Copy everything for the agent.
        pause(0.8)
        tap(app.buttons["Copy annotations"])
        pause(3)
    }

    // MARK: - Helpers

    private func write(_ text: String, intent: String) {
        let note = app.textViews["Note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        pause(0.6)
        log(.zero, kind: 3)
        note.typeText(text)
        log(.zero, kind: 4)
        pause(0.6)
        tap(app.segmentedControls.buttons[intent])
        pause(0.6)
        tap(app.buttons["Save"])
        XCTAssertTrue(note.waitForNonExistence(timeout: 3))
        pause(1.4)
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let frame = element.frame
        tap(at: CGPoint(x: frame.midX, y: frame.midY))
    }

    private func tap(at point: CGPoint) {
        log(point, kind: 0)
        coordinate(point).tap()
    }

    private func coordinate(_ point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
    }

    /// kind: 0 tap, 1 drag start, 2 drag end, 3 typing starts, 4 typing ends. Time is wall clock, shared with the Mac.
    private func log(_ point: CGPoint, kind: Double) {
        events.append(["t": Date().timeIntervalSince1970, "x": point.x, "y": point.y, "kind": kind])
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
