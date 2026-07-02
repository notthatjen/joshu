import Foundation
import GRDB

public struct ActionItem: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var text: String
    public var owner: String?
    public var isImmediate: Bool
    public var suggestedPrompt: String?

    enum CodingKeys: String, CodingKey {
        case text, owner, isImmediate, suggestedPrompt
    }
}

/// Persisted so a meeting is processed exactly once across relaunches.
public struct ProcessedMeeting: Codable, Identifiable, Hashable, Sendable,
    FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "processed_meeting"

    public var id: String // Granola document id
    public var title: String
    public var processedAt: Date
    public var actionItemsJSON: Data

    public var actionItems: [ActionItem] {
        (try? JSONDecoder().decode([ActionItem].self, from: actionItemsJSON)) ?? []
    }
}

/// Meeting-history store (GRDB, same DB file family as reviews).
public final class MeetingStore: Sendable {
    private let queue: DatabaseQueue

    public init(path: String) throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        queue = try DatabaseQueue(path: path)
        try migrator.migrate(queue)
    }

    public init() throws {
        queue = try DatabaseQueue()
        try migrator.migrate(queue)
    }

    public static func defaultPath() -> String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Joshu/meetings.sqlite").path
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: ProcessedMeeting.databaseTableName) { table in
                table.primaryKey("id", .text)
                table.column("title", .text).notNull()
                table.column("processedAt", .datetime).notNull()
                table.column("actionItemsJSON", .blob).notNull()
            }
        }
        return migrator
    }

    public func isProcessed(_ id: String) throws -> Bool {
        try queue.read { db in
            try ProcessedMeeting.filter(key: id).fetchCount(db) > 0
        }
    }

    public func markProcessed(_ meeting: ProcessedMeeting) throws {
        var meeting = meeting
        try queue.write { db in try meeting.save(db) }
    }

    public func recent(limit: Int = 50) throws -> [ProcessedMeeting] {
        try queue.read { db in
            try ProcessedMeeting
                .order(Column("processedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
