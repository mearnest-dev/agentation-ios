import XCTest
@testable import Agentation

final class MarkdownFormatterTests: XCTestCase {
    func testElementAnnotation() {
        let output = MarkdownFormatter.annotation(makeAnnotation(), number: 1)
        XCTAssertTrue(output.hasPrefix("## [style] Annotation 1\n"))
        XCTAssertTrue(output.contains("**Screen:** `CheckoutView`"))
        XCTAssertTrue(output.contains("**Element:** `Button`"))
        XCTAssertTrue(output.contains("**Identifier:** `checkout.payButton`"))
        XCTAssertTrue(output.contains("**Tag:** `PaymentSummaryCard`"))
        XCTAssertTrue(output.contains("**Source:** `Demo/CheckoutView.swift:42`"))
        XCTAssertTrue(output.contains("**Frame:** `x=16 y=712 w=361 h=50`"))
        XCTAssertTrue(output.contains("**Text:** \"Pay $42.00\""))
        XCTAssertTrue(output.contains("**Nearby text:** \"Total\", \"$42.00\""))
        XCTAssertTrue(output.contains("**Screenshot:** `/tmp/agentation/annotation-a1.png`"))
        XCTAssertTrue(output.hasSuffix("**Note:** corners should be 16"))
        // Accessibility label equals the text, so it is not repeated.
        XCTAssertFalse(output.contains("Accessibility label"))
    }

    func testAnnotationWithoutIntent() {
        let output = MarkdownFormatter.annotation(makeAnnotation(intent: nil), number: 3)
        XCTAssertTrue(output.hasPrefix("## Annotation 3\n"))
    }

    func testAreaAnnotation() {
        let output = MarkdownFormatter.annotation(makeAnnotation(intent: .bug, isArea: true), number: 2)
        XCTAssertTrue(output.contains("**Area:** `x=16 y=712 w=361 h=50`"))
        XCTAssertTrue(output.contains("**Inside:** `PaymentSummaryCard`"))
        XCTAssertTrue(output.contains("**Contains:** `ShippingOptions`"))
        XCTAssertTrue(output.contains("**Text in area:**"))
        XCTAssertFalse(output.contains("**Element:**"))
        XCTAssertFalse(output.contains("**Frame:**"))
    }

    func testDocumentHeader() {
        let device = DeviceInfo(
            model: "iPhone 16 Pro Simulator", systemVersion: "26.0",
            screenSize: CGSize(width: 393, height: 852), scale: 3, isDarkMode: false, contentSize: "L")
        let output = MarkdownFormatter.document(
            [makeAnnotation(id: "a"), makeAnnotation(id: "b")],
            appName: "MyApp", bundleID: "com.example.myapp", device: device)
        XCTAssertTrue(output.hasPrefix("# iOS feedback: MyApp (com.example.myapp)\n"))
        XCTAssertTrue(output.contains("Device: iPhone 16 Pro Simulator, iOS 26.0, 393×852pt @3x, light mode, Dynamic Type L"))
        XCTAssertTrue(output.contains("## [style] Annotation 1"))
        XCTAssertTrue(output.contains("## [style] Annotation 2"))
    }

    func testCodeEscapesBackticks() {
        XCTAssertEqual(MarkdownFormatter.code("a`b"), "`a'b`")
    }

    func testRectNumberFormatting() {
        XCTAssertEqual(Rect.number(16), "16")
        XCTAssertEqual(Rect.number(16.04), "16")
        XCTAssertEqual(Rect.number(16.25), "16.3")
    }
}
