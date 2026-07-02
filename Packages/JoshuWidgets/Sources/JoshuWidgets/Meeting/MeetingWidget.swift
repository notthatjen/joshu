import SwiftUI
import Observation
import JoshuKit

public struct MeetingConfig: WidgetConfig {
    /// Where "Run with Claude" spawns sessions. Empty → ask each time.
    public var defaultWorkspacePath: String = ""
    public init() {}
}

/// Detects finished Granola meetings, extracts action items, and surfaces
/// immediate ones as edge toasts with Copy / Run-with-Claude.
public enum MeetingWidget: WidgetDescriptor {
    public static let typeID = WidgetTypeID(rawValue: "com.wren.joshu.meeting")

    public static let metadata = WidgetMetadata(
        displayName: "Meeting",
        systemImage: "waveform.badge.mic",
        summary: "Pulls finished Granola meetings and turns action items into agent tasks.",
        defaultSize: CGSize(width: 340, height: 400),
        allowsMultipleInstances: false
    )

    public static func makeView(model: WidgetModel<MeetingConfig>) -> some View {
        MeetingView(model: model)
    }

    public static func makeService(model: WidgetModel<MeetingConfig>) -> (any WidgetService)? {
        MeetingService.shared(model: model)
    }
}

/// Background poller (a WidgetService, so it keeps running while the widget
/// is hidden). Shared singleton because the widget disallows multiple
/// instances and the toast host is app-global.
@MainActor
@Observable
public final class MeetingService: WidgetService {
    public private(set) var recent: [ProcessedMeeting] = []
    public private(set) var statusText: String?
    public private(set) var needsConnect = false
    public var defaultWorkspacePath: String

    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private let source: MeetingSource
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    private static var instance: MeetingService?

    static func shared(model: WidgetModel<MeetingConfig>) -> MeetingService {
        if let instance {
            instance.defaultWorkspacePath = model.config.defaultWorkspacePath
            return instance
        }
        let store = (try? MeetingStore(path: MeetingStore.defaultPath())) ?? (try! MeetingStore())
        let service = MeetingService(
            store: store, source: GranolaSource(),
            defaultWorkspacePath: model.config.defaultWorkspacePath)
        instance = service
        return service
    }

    init(store: MeetingStore, source: MeetingSource, defaultWorkspacePath: String) {
        self.store = store
        self.source = source
        self.defaultWorkspacePath = defaultWorkspacePath
        recent = (try? store.recent()) ?? []
    }

    public func start() async {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll(allowKeychainPrompt: false)
                try? await Task.sleep(for: .seconds(45))
            }
        }
    }

    public func stop() async {
        pollTask?.cancel()
    }

    /// Explicit user action: allowed to trigger the one-time Keychain prompt.
    func connect() async {
        await poll(allowKeychainPrompt: true)
    }

    func poll(allowKeychainPrompt: Bool) async {
        do {
            let meetings = try await source.recentMeetings(
                since: nil, allowKeychainPrompt: allowKeychainPrompt)
            statusText = nil
            needsConnect = false
            for meeting in meetings {
                guard !(try store.isProcessed(meeting.id)) else { continue }
                await process(meeting)
            }
        } catch MeetingSourceError.needsConnect {
            needsConnect = true
            statusText = nil
        } catch {
            statusText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func process(_ meeting: MeetingRef) async {
        guard let claude = await sharedToolAvailability.url(for: .claude) else { return }
        let transcript = (try? await source.transcript(for: meeting.id)) ?? ""
        guard !transcript.isEmpty else { return } // not ready yet; retry next poll

        let items = (try? await ActionItemExtractor.extract(
            transcript: transcript, meetingTitle: meeting.title, claude: claude)) ?? []

        let processed = ProcessedMeeting(
            id: meeting.id, title: meeting.title, processedAt: Date(),
            actionItemsJSON: (try? JSONEncoder().encode(items)) ?? Data("[]".utf8))
        try? store.markProcessed(processed)
        recent = (try? store.recent()) ?? []

        for item in items where item.isImmediate {
            ToastCenter.shared.present(
                ActionToast(item: item, meetingTitle: meeting.title,
                            defaultWorkspace: defaultWorkspacePath))
        }
    }
}

// MARK: - Widget view

private struct MeetingView: View {
    @Bindable var model: WidgetModel<MeetingConfig>
    @State private var service: MeetingService

    init(model: WidgetModel<MeetingConfig>) {
        self.model = model
        _service = State(initialValue: MeetingService.shared(model: model))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Meetings", systemImage: "waveform.badge.mic")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Default workspace for Run with Claude", text: $model.config.defaultWorkspacePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            if service.needsConnect {
                HStack(spacing: 8) {
                    Text("Granola credentials are encrypted.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Button("Connect") {
                        Task { await service.connect() }
                    }
                    .controlSize(.small)
                }
            }

            if let statusText = service.statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if service.recent.isEmpty {
                Spacer()
                Text(service.needsConnect
                     ? "Connect to start watching meetings."
                     : "Watching Granola for finished meetings…")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(service.recent) { meeting in
                            MeetingRow(meeting: meeting, workspace: model.config.defaultWorkspacePath)
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}

private struct MeetingRow: View {
    let meeting: ProcessedMeeting
    let workspace: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            ForEach(meeting.actionItems) { item in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: item.isImmediate ? "bolt.fill" : "circle")
                        .font(.caption2)
                        .foregroundStyle(item.isImmediate ? .yellow : .white.opacity(0.4))
                    Text(item.text)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
