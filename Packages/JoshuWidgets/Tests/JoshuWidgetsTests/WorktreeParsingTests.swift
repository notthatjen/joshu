import XCTest
@testable import JoshuWidgets

final class WorktreeParsingTests: XCTestCase {
    func testParsesPorcelainStanzas() {
        let porcelain = """
        worktree /Users/x/repo
        HEAD abc123
        branch refs/heads/main

        worktree /Users/x/repo/.claude/worktrees/feature
        HEAD def456
        branch refs/heads/feat/thing

        worktree /Users/x/gone
        HEAD 000000
        detached
        prunable gitdir file points to non-existent location
        """

        let trees = CodingServices.parseWorktrees(porcelain: porcelain)
        XCTAssertEqual(trees.count, 3)
        XCTAssertEqual(trees[0].path, "/Users/x/repo")
        XCTAssertEqual(trees[0].branch, "main")
        XCTAssertFalse(trees[0].prunable)
        XCTAssertEqual(trees[1].branch, "feat/thing")
        XCTAssertEqual(trees[1].displayName, "feat/thing")
        XCTAssertNil(trees[2].branch)
        XCTAssertTrue(trees[2].prunable)
        XCTAssertEqual(trees[2].displayName, "gone")
    }

    func testEmptyOutput() {
        XCTAssertTrue(CodingServices.parseWorktrees(porcelain: "").isEmpty)
    }
}
