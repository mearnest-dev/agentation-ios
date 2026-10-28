import XCTest

/// Drives the Agentation toolbar in the demo app end to end.
///
/// Run with a fresh install so no annotations are left over:
///   xcrun simctl uninstall booted dev.mearnest.AgentationDemo
///   xcodebuild test -project AgentationDemo.xcodeproj -scheme AgentationDemo -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
///
/// Set TEST_RUNNER_SCREENSHOT_DIR to a Mac folder to also save step screenshots there.
final class AgentationFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testFullFlow() {
        // Collapsed toolbar: one button.
        let show = app.buttons["Show Agentation"]
        XCTAssertTrue(show.waitForExistence(timeout: 10))
        snapshot("01-collapsed")

        clearIfNeeded()
        show.tap()
        XCTAssertTrue(app.buttons["Inspect"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Hide Agentation"].exists)
        snapshot("02-expanded")

        // Copy with nothing saved.
        app.buttons["Copy annotations"].tap()
        XCTAssertTrue(app.staticTexts["No annotations yet"].waitForExistence(timeout: 3))

        // Inspect the SwiftUI pay button.
        let payFrame = app.buttons["checkout.payButton"].frame
        XCTAssertFalse(payFrame.isEmpty)
        app.buttons["Inspect"].tap()
        tap(at: payFrame)
        let inspect = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'identifier: checkout.payButton'")).firstMatch
        XCTAssertTrue(inspect.waitForExistence(timeout: 3), "Inspect panel should show the pay button identifier")
        XCTAssertTrue(inspect.label.contains("tag: PaymentSummaryCard"), inspect.label)
        XCTAssertTrue(inspect.label.contains("source: AgentationDemo/CheckoutView.swift:"), inspect.label)
        XCTAssertTrue(inspect.label.contains("screen: Checkout"), inspect.label)
        snapshot("03-inspect")

        // Inspect -> Annotate opens the editor for the same element.
        app.buttons["Annotate"].firstMatch.tap()
        saveNote("Corners should be 12 to match the cards", intent: "Style")
        XCTAssertTrue(app.buttons["Annotation 1"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["Copy annotations"].value as? String, "1 annotations")
        snapshot("04-annotated")

        // Annotate mode: tap the gift note field.
        let giftFrame = app.textFields["checkout.giftNote"].frame
        tap(at: giftFrame)
        saveNote("Placeholder is too vague", intent: "Content")
        XCTAssertTrue(app.buttons["Annotation 2"].waitForExistence(timeout: 3))

        // Cancelling the editor saves nothing.
        tap(at: app.staticTexts["Total"].frame)
        let note = app.textViews["Note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Save"].isEnabled, "Save should be disabled with an empty note")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Annotation 3"].exists)

        // Area select: drag across the cart card.
        let window = app.windows.firstMatch.frame
        let start = point(x: window.minX + 30, y: window.minY + 200)
        let end = point(x: window.maxX - 30, y: window.minY + 320)
        start.press(forDuration: 0.05, thenDragTo: end)
        saveNote("Cart card needs more spacing", intent: "Bug")
        XCTAssertTrue(app.buttons["Annotation 3"].waitForExistence(timeout: 3))
        snapshot("05-area")

        // Edit an existing marker.
        app.buttons["Annotation 2"].tap()
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertEqual(note.value as? String, "Placeholder is too vague")
        note.typeText(" for users")
        app.buttons["Save"].tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 3))

        // UIKit screen: switch tabs with the toolbar closed, then annotate the edit button.
        app.buttons["Hide Agentation"].tap()
        XCTAssertFalse(app.buttons["Annotation 1"].exists, "Markers hide when the toolbar is closed")
        app.tabBars.buttons["Settings (UIKit)"].tap()
        let editProfile = app.buttons["settings.editProfile"]
        XCTAssertTrue(editProfile.waitForExistence(timeout: 3))
        app.buttons["Show Agentation"].tap()
        XCTAssertFalse(app.buttons["Annotation 1"].exists, "Markers are per screen")
        app.buttons["Annotate"].tap()
        tap(at: editProfile.frame)
        saveNote("Button should be full width", intent: nil)
        XCTAssertTrue(app.buttons["Annotation 4"].waitForExistence(timeout: 3))
        snapshot("06-uikit")

        // Delete it via the editor.
        app.buttons["Annotation 4"].tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["Annotation 4"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.buttons["Copy annotations"].value as? String, "3 annotations")

        // Copy all.
        app.buttons["Copy annotations"].tap()
        XCTAssertTrue(app.staticTexts["Copied 3 annotations"].waitForExistence(timeout: 3))

        // Annotations survive a relaunch.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Show Agentation"].waitForExistence(timeout: 10))
        app.buttons["Show Agentation"].tap()
        XCTAssertEqual(app.buttons["Copy annotations"].value as? String, "3 annotations")
        XCTAssertTrue(app.buttons["Annotation 1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Annotation 3"].exists)
        snapshot("07-relaunched")

        // Leave the annotations in place and copied, so the run can be checked from the Mac.
        app.buttons["Copy annotations"].tap()
        XCTAssertTrue(app.staticTexts["Copied 3 annotations"].waitForExistence(timeout: 3))
    }

    func testClearScreenAndAll() {
        let show = app.buttons["Show Agentation"]
        XCTAssertTrue(show.waitForExistence(timeout: 10))
        clearIfNeeded()
        show.tap()

        app.buttons["Annotate"].tap()
        tap(at: app.buttons["checkout.payButton"].frame)
        saveNote("one", intent: nil)
        XCTAssertTrue(app.buttons["Annotation 1"].waitForExistence(timeout: 3))

        app.buttons["Clear annotations"].tap()
        let thisScreen = app.buttons["This screen (1)"]
        XCTAssertTrue(thisScreen.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["All screens (1)"].exists)
        thisScreen.tap()
        XCTAssertTrue(app.buttons["Annotation 1"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.buttons["Copy annotations"].value as? String, "0 annotations")

        app.buttons["Clear annotations"].tap()
        XCTAssertTrue(app.staticTexts["Nothing to clear"].waitForExistence(timeout: 3))
    }

    // MARK: - Helpers

    /// Removes leftovers from earlier runs.
    private func clearIfNeeded() {
        XCTAssertTrue(app.buttons["checkout.payButton"].waitForExistence(timeout: 10))
        app.buttons["Show Agentation"].tap()
        XCTAssertTrue(app.buttons["Clear annotations"].waitForExistence(timeout: 3))
        if app.buttons["Copy annotations"].value as? String != "0 annotations" {
            app.buttons["Clear annotations"].tap()
            let all = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'All screens'")).firstMatch
            XCTAssertTrue(all.waitForExistence(timeout: 3))
            all.tap()
        }
        app.buttons["Hide Agentation"].tap()
    }

    private func saveNote(_ text: String, intent: String?) {
        let note = app.textViews["Note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), "Editor should open")
        note.typeText(text)
        if let intent { app.segmentedControls.buttons[intent].tap() }
        app.buttons["Save"].tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 3))
    }

    private func point(x: CGFloat, y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }

    private func tap(at frame: CGRect) {
        point(x: frame.midX, y: frame.midY).tap()
    }

    private func snapshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
