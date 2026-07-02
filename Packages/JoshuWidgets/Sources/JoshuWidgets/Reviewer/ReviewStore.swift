import Foundation
import GRDB

/// SQLite persistence for review history (GRDB). Unlike widget instances
/// (a handful of JSON records), review runs accumulate and get queried by
/// subject — a real table earns its keep here.
public final class ReviewStore: Sendable {
    private let queue: DatabaseQueue

    public init(path: String) throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        queue = try DatabaseQueue(path: path)
        try migrator.migrate(queue)
    }

    /// In-memory store for tests.
    public init() throws {
        queue = try DatabaseQueue()
        try migrator.migrate(queue)
    }

    public static func defaultPath() -> String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Joshu/reviews.sqlite").path
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: ReviewRun.databaseTableName) { table in
                table.primaryKey("id", .text)
                table.column("url", .text).notNull()
                table.column("owner", .text).notNull()
                table.column("repo", .text).notNull()
                table.column("prNumber", .integer).notNull()
                table.column("title", .text).notNull()
                table.column("author", .text).notNull()
                table.column("headSHA", .text).notNull()
                table.column("baseRef", .text).notNull()
                table.column("prState", .text).notNull()
                table.column("status", .text).notNull()
                table.column("findingsJSON", .blob).notNull()
                table.column("summary", .text)
                table.column("promptVersion", .integer).notNull()
                table.column("errorMessage", .text)
                table.column("createdAt", .datetime).notNull()
                table.column("completedAt", .datetime)
                table.column("lastCheckedAt", .datetime)
            }
            try db.create(
                indexOn: ReviewRun.databaseTableName,
                columns: ["owner", "repo", "prNumber", "createdAt"])
        }
        return migrator
    }

    // MARK: - CRUD

    public func save(_ run: ReviewRun) throws {
        var run = run
        try queue.write { db in
            try run.save(db)
        }
    }

    public func allRuns() throws -> [ReviewRun] {
        try queue.read { db in
            try ReviewRun
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    /// Latest run per PR, newest first — the widget's list view.
    public func latestPerSubject() throws -> [ReviewRun] {
        let runs = try allRuns()
        var seen = Set<String>()
        return runs.filter { seen.insert($0.subjectKey).inserted }
    }

    public func runs(for ref: PRRef) throws -> [ReviewRun] {
        try queue.read { db in
            try ReviewRun
                .filter(Column("owner") == ref.owner)
                .filter(Column("repo") == ref.repo)
                .filter(Column("prNumber") == ref.number)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    public func delete(id: UUID) throws {
        _ = try queue.write { db in
            try ReviewRun.deleteOne(db, key: id.uuidString)
        }
    }
}
