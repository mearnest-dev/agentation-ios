import XCTest
@testable import Agentation

final class AnnotationStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentation-tests-\(UUID().uuidString)")
            .appendingPathComponent("annotations.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        super.tearDown()
    }

    func testPersistsAcrossInstances() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = AnnotationStore(fileURL: fileURL, now: now)
        store.add(makeAnnotation(id: "a"))
        store.add(makeAnnotation(id: "b"))
        store.setServerId("server-b", for: "b")

        let reloaded = AnnotationStore(fileURL: fileURL, now: now)
        XCTAssertEqual(reloaded.annotations.map(\.id), ["a", "b"])
        XCTAssertEqual(reloaded.annotation(id: "b")?.serverId, "server-b")
    }

    func testUpdateAndRemove() {
        let store = AnnotationStore(fileURL: fileURL)
        store.add(makeAnnotation(id: "a"))
        var updated = makeAnnotation(id: "a")
        updated.comment = "changed"
        store.update(updated)
        XCTAssertEqual(store.annotation(id: "a")?.comment, "changed")
        store.remove(id: "a")
        XCTAssertTrue(store.annotations.isEmpty)
    }

    func testDropsAnnotationsOlderThanSevenDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = AnnotationStore(fileURL: fileURL, now: now)
        store.add(makeAnnotation(id: "old", timestamp: now.timeIntervalSince1970 - AnnotationStore.maxAge - 60))
        store.add(makeAnnotation(id: "new", timestamp: now.timeIntervalSince1970 - 60))

        let reloaded = AnnotationStore(fileURL: fileURL, now: now)
        XCTAssertEqual(reloaded.annotations.map(\.id), ["new"])
    }
}
