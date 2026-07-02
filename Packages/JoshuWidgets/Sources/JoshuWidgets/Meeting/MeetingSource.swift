import Foundation

/// A completed meeting with a transcript available.
public struct MeetingRef: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let endedAt: Date?

    public init(id: String, title: String, endedAt: Date?) {
        self.id = id
        self.title = title
        self.endedAt = endedAt
    }
}

/// Widget code depends only on this — A1 (official API), A2
/// (reverse-engineered), or a local-decrypt source all conform, so the M8a
/// decision can change without touching the widget.
public protocol MeetingSource: Sendable {
    /// Recently completed meetings (newest first), optionally since a date.
    /// `allowKeychainPrompt` gates the one-time credential-decrypt prompt so
    /// background polling never surprises the user.
    func recentMeetings(since: Date?, allowKeychainPrompt: Bool) async throws -> [MeetingRef]
    func transcript(for id: String) async throws -> String
}

public enum MeetingSourceError: Error, LocalizedError {
    case notAuthenticated
    case needsConnect
    case granolaNotInstalled
    case tokenUnavailable(String)
    case http(Int, String)
    case decode(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Granola isn't signed in — open Granola and sign in."
        case .needsConnect: "Connect Granola to read meetings (one-time Keychain access)."
        case .granolaNotInstalled: "Granola isn't installed."
        case .tokenUnavailable(let why): "Couldn't read Granola credentials: \(why)"
        case .http(let code, let message): "Granola API \(code): \(message)"
        case .decode(let what): "Unexpected Granola response: \(what)"
        }
    }
}
