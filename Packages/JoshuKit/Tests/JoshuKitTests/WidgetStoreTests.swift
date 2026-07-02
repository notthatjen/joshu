import XCTest
@testable import JoshuKit

@MainActor
final class WidgetStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("joshu-tests-\(UUID().uuidString)/widgets.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
        super.tearDown()
    }

    private func makeRecord(typeID: String = "com.wren.joshu.test") -> WidgetInstanceRecord {
        WidgetInstanceRecord(
            typeID: WidgetTypeID(rawValue: typeID),
            configJSON: Data(#"{"text":"hello"}"#.utf8),
            placement: PanelPlacement(origin: CGPoint(x: 100, y: 200), size: CGSize(width: 420, height: 320))
        )
    }

    func testRoundTrip() {
        let store = WidgetStore(fileURL: tempURL)
        let record = makeRecord()
        store.add(record)
        store.saveNow()

        let reloaded = WidgetStore(fileURL: tempURL)
        XCTAssertEqual(reloaded.records, [record])
    }

    func testMutationsPersist() {
        let store = WidgetStore(fileURL: tempURL)
        let record = makeRecord()
        store.add(record)
        store.updateConfig(id: record.id, configJSON: Data(#"{"text":"edited"}"#.utf8))
        store.updatePlacement(id: record.id, placement: PanelPlacement(origin: CGPoint(x: 5, y: 6), size: CGSize(width: 1, height: 2)))
        store.saveNow()

        let reloaded = WidgetStore(fileURL: tempURL)
        XCTAssertEqual(reloaded.records.first?.configJSON, Data(#"{"text":"edited"}"#.utf8))
        XCTAssertEqual(reloaded.records.first?.placement.origin, CGPoint(x: 5, y: 6))
    }

    func testRemove() {
        let store = WidgetStore(fileURL: tempURL)
        let record = makeRecord()
        store.add(record)
        store.remove(id: record.id)
        store.saveNow()

        XCTAssertTrue(WidgetStore(fileURL: tempURL).records.isEmpty)
    }

    func testUnknownTypeIDSurvivesRoundTrip() {
        let store = WidgetStore(fileURL: tempURL)
        store.add(makeRecord(typeID: "com.wren.joshu.from-the-future"))
        store.saveNow()

        let reloaded = WidgetStore(fileURL: tempURL)
        XCTAssertEqual(reloaded.records.first?.typeID.rawValue, "com.wren.joshu.from-the-future")

        // Saving again must not drop the unknown-type record.
        reloaded.saveNow()
        XCTAssertEqual(WidgetStore(fileURL: tempURL).records.count, 1)
    }

    func testCorruptedFileMovedToBakAndStartsFresh() throws {
        try FileManager.default.createDirectory(
            at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json {{{".utf8).write(to: tempURL)

        let store = WidgetStore(fileURL: tempURL)
        XCTAssertTrue(store.records.isEmpty)

        let backup = tempURL.appendingPathExtension("bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))

        // Store is usable after recovery.
        store.add(makeRecord())
        store.saveNow()
        XCTAssertEqual(WidgetStore(fileURL: tempURL).records.count, 1)
    }

    func testMissingFileStartsEmpty() {
        XCTAssertTrue(WidgetStore(fileURL: tempURL).records.isEmpty)
    }
}
