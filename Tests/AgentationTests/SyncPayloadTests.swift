import XCTest
@testable import Agentation

final class SyncPayloadTests: XCTestCase {
    func testPayloadMatchesAgentationShape() throws {
        let payload = ServerAnnotationPayload(makeAnnotation(intent: .bug))
        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["comment"] as? String, "corners should be 16")
        XCTAssertEqual(json["element"] as? String, "Button")
        XCTAssertNotNil(json["elementPath"] as? String)
        XCTAssertEqual(json["timestamp"] as? Double, 1_800_000_000_000)
        XCTAssertEqual(json["intent"] as? String, "fix")
        XCTAssertEqual(json["kind"] as? String, "feedback")
        XCTAssertEqual(json["url"] as? String, "ios-sim://dev.example.app/CheckoutView")
        XCTAssertNil(json["isMultiSelect"])

        let box = try XCTUnwrap(json["boundingBox"] as? [String: Double])
        XCTAssertEqual(box["width"], 361)

        let attributes = try XCTUnwrap(json["attributes"] as? [String: String])
        XCTAssertEqual(attributes["platform"], "ios")
        XCTAssertEqual(attributes["category"], "bug")
        XCTAssertEqual(attributes["accessibilityIdentifier"], "checkout.payButton")
        XCTAssertEqual(attributes["screenshotPath"], "/tmp/agentation/annotation-a1.png")
    }

    func testIntentMapping() {
        XCTAssertNil(ServerAnnotationPayload.serverIntent(nil))
        XCTAssertEqual(ServerAnnotationPayload.serverIntent(.bug), "fix")
        XCTAssertEqual(ServerAnnotationPayload.serverIntent(.style), "change")
        XCTAssertEqual(ServerAnnotationPayload.serverIntent(.content), "change")
    }

    func testAreaIsMultiSelect() throws {
        let data = try JSONEncoder().encode(ServerAnnotationPayload(makeAnnotation(isArea: true)))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["isMultiSelect"] as? Bool, true)
    }

    func testRejectsInvalidEndpoint() {
        XCTAssertNil(SyncClient(endpoint: "localhost:4747", sessionURL: "ios-sim://app"))
        XCTAssertEqual(
            SyncClient(endpoint: "http://localhost:4747/", sessionURL: "ios-sim://app")?.endpoint.absoluteString,
            "http://localhost:4747")
    }
}
