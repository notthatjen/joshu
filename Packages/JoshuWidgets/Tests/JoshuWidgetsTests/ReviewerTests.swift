import XCTest
@testable import JoshuWidgets

final class PRRefTests: XCTestCase {
    func testParsesStandardURL() {
        let ref = PRRef.parse("https://github.com/wren/joshu/pull/42")
        XCTAssertEqual(ref, PRRef(owner: "wren", repo: "joshu", number: 42))
    }

    func testParsesWithTrailingPathAndWhitespace() {
        let ref = PRRef.parse("  https://github.com/a-b/c.d/pull/7/files?diff=split \n")
        XCTAssertEqual(ref, PRRef(owner: "a-b", repo: "c.d", number: 7))
    }

    func testRejectsNonPRURLs() {
        XCTAssertNil(PRRef.parse("https://github.com/wren/joshu/issues/42"))
        XCTAssertNil(PRRef.parse("https://github.com/wren/joshu"))
        XCTAssertNil(PRRef.parse("not a url"))
    }
}

final class FindingsPayloadTests: XCTestCase {
    private let clean = #"{"summary":"looks fine","findings":[{"severity":"high","file":"a.swift","line":10,"title":"crash","detail":"nil unwrap"}]}"#

    func testExtractsCleanJSON() {
        let payload = FindingsPayload.extract(from: clean)
        XCTAssertEqual(payload?.summary, "looks fine")
        XCTAssertEqual(payload?.findings.count, 1)
        XCTAssertEqual(payload?.findings.first?.severity, .high)
    }

    func testExtractsFencedJSONWithProse() {
        let wrapped = "Here is my review:\n```json\n\(clean)\n```\nHope that helps!"
        let payload = FindingsPayload.extract(from: wrapped)
        XCTAssertEqual(payload?.findings.count, 1)
    }

    func testExtractsBraceSpanAsLastResort() {
        let wrapped = "REVIEW RESULT >>> \(clean) <<< END"
        let payload = FindingsPayload.extract(from: wrapped)
        XCTAssertEqual(payload?.summary, "looks fine")
    }

    func testNilLineTolerated() {
        let noLine = #"{"summary":"s","findings":[{"severity":"nit","file":"b.swift","line":null,"title":"t","detail":"d"}]}"#
        XCTAssertNil(FindingsPayload.extract(from: noLine)?.findings.first?.line)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(FindingsPayload.extract(from: "I could not review this PR."))
    }
}

final class ReviewStoreTests: XCTestCase {
    private func makeRun(pr: Int = 1, status: ReviewStatus = .completed, createdAt: Date = Date()) -> ReviewRun {
        ReviewRun(
            id: UUID(), url: "https://github.com/o/r/pull/\(pr)", owner: "o", repo: "r",
            prNumber: pr, title: "PR \(pr)", author: "jen", headSHA: "abc",
            baseRef: "main", prState: "OPEN", status: status,
            findingsJSON: Data(#"[{"severity":"low","file":"x","line":null,"title":"t","detail":"d"}]"#.utf8),
            summary: "sum", promptVersion: 1, errorMessage: nil,
            createdAt: createdAt, completedAt: nil, lastCheckedAt: nil)
    }

    func testRoundTrip() throws {
        let store = try ReviewStore()
        let run = makeRun()
        try store.save(run)

        let loaded = try store.allRuns()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, run.id)
        XCTAssertEqual(loaded.first?.findings.count, 1)
        XCTAssertEqual(loaded.first?.findings.first?.severity, .low)
    }

    func testLatestPerSubjectKeepsNewestRunOnly() throws {
        let store = try ReviewStore()
        try store.save(makeRun(pr: 1, createdAt: Date(timeIntervalSinceNow: -100)))
        var newer = makeRun(pr: 1, createdAt: Date())
        newer.headSHA = "def"
        try store.save(newer)
        try store.save(makeRun(pr: 2))

        let latest = try store.latestPerSubject()
        XCTAssertEqual(latest.count, 2)
        XCTAssertEqual(latest.first { $0.prNumber == 1 }?.headSHA, "def")

        // Full history still there.
        XCTAssertEqual(try store.runs(for: PRRef(owner: "o", repo: "r", number: 1)).count, 2)
    }

    func testUpdateInPlace() throws {
        let store = try ReviewStore()
        var run = makeRun(status: .running)
        try store.save(run)
        run.status = .completed
        try store.save(run)

        XCTAssertEqual(try store.allRuns().count, 1)
        XCTAssertEqual(try store.allRuns().first?.status, .completed)
    }
}
