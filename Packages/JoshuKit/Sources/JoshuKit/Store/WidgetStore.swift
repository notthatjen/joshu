import Foundation
import Observation
import os

/// Source of truth for widget instances. JSON file, atomic writes, debounced
/// saves; a corrupted file is renamed to .bak and the store starts fresh
/// rather than crashing.
@MainActor
@Observable
public final class WidgetStore {
    public private(set) var records: [WidgetInstanceRecord] = []

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "com.wren.joshu", category: "WidgetStore")

    private struct StoreFile: Codable {
        var schemaVersion: Int
        var instances: [WidgetInstanceRecord]
    }

    private static let currentSchemaVersion = 1

    public init(fileURL: URL) {
        self.fileURL = fileURL
        records = Self.load(from: fileURL)
    }

    /// Default production location: ~/Library/Application Support/Joshu/widgets.json
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Joshu/widgets.json")
    }

    // MARK: - Mutations

    public func add(_ record: WidgetInstanceRecord) {
        records.append(record)
        scheduleSave()
    }

    public func remove(id: UUID) {
        records.removeAll { $0.id == id }
        scheduleSave()
    }

    public func updateConfig(id: UUID, configJSON: Data) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].configJSON = configJSON
        scheduleSave()
    }

    public func updatePlacement(id: UUID, placement: PanelPlacement) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].placement = placement
        scheduleSave()
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.performSave()
        }
    }

    /// Immediate save — call on app termination so debounced writes aren't lost.
    public func saveNow() {
        saveTask?.cancel()
        performSave()
    }

    private func performSave() {
        let file = StoreFile(schemaVersion: Self.currentSchemaVersion, instances: records)
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(file).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("save failed: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> [WidgetInstanceRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode(StoreFile.self, from: data).instances
        } catch {
            // Corrupted or future-schema file: preserve it for forensics and
            // start clean instead of crashing on launch.
            let backup = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            Logger(subsystem: "com.wren.joshu", category: "WidgetStore")
                .error("widgets.json unreadable, moved to .bak: \(error.localizedDescription)")
            return []
        }
    }
}
