#if os(macOS)
import Foundation
import CoreServices

/// FSEvents wrapper: watches directory trees and yields the set of changed
/// paths, coalesced by FSEvents' own latency. FSEvents tells you *that*
/// something under a directory changed — do a cheap stat/tail afterwards to
/// learn *what*. Survives atomic write-rename patterns that break
/// single-fd DispatchSource watchers.
public final class FileWatcher: @unchecked Sendable {
    public let events: AsyncStream<Set<URL>>

    private var streamRef: FSEventStreamRef?
    private let continuation: AsyncStream<Set<URL>>.Continuation
    private let queue = DispatchQueue(label: "com.wren.joshu.filewatcher")

    public init(paths: [URL], latency: TimeInterval = 0.3) {
        var continuation: AsyncStream<Set<URL>>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation

        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            // kFSEventStreamCreateFlagUseCFTypes makes eventPaths a CFArray
            // of CFString; without it this would be a raw char**.
            guard let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] else { return }
            let urls = Set(paths.prefix(count).map { URL(fileURLWithPath: $0) })
            watcher.continuation.yield(urls)
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer)
        ) else {
            continuation.finish()
            return
        }

        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream = streamRef else { return }
        streamRef = nil
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        continuation.finish()
    }

    deinit {
        stop()
    }
}
#endif
