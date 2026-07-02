import Foundation

/// A2 MeetingSource: Granola's app API with the locally-stored WorkOS token.
/// Endpoint + client-gate confirmed in M8a (docs/integrations/granola.md).
public struct GranolaSource: MeetingSource {
    private let base = URL(string: "https://api.granola.ai")!
    private let clientVersion: String
    private let tokenStore = GranolaTokenStore()

    public init(clientVersion: String = "7.373.2") {
        self.clientVersion = clientVersion
    }

    public func recentMeetings(since: Date?, allowKeychainPrompt: Bool) async throws -> [MeetingRef] {
        var body: [String: Any] = ["limit": 20]
        if let since {
            body["created_after"] = ISO8601DateFormatter().string(from: since)
        }
        let json = try await post("/v2/get-documents", body: body, allowKeychainPrompt: allowKeychainPrompt)
        let docs = (json["docs"] ?? json["documents"]) as? [[String: Any]] ?? []
        return docs.compactMap(Self.meetingRef).filter { $0.endedAt != nil }
    }

    public func transcript(for id: String) async throws -> String {
        let json = try await post("/v1/get-document-transcript", body: ["document_id": id], allowKeychainPrompt: true)
        // Transcript comes back as segments; concatenate speaker + text.
        if let segments = json["transcript"] as? [[String: Any]] ?? json["segments"] as? [[String: Any]] {
            return segments.compactMap { segment in
                let speaker = segment["speaker"] as? String ?? segment["source"] as? String
                let text = segment["text"] as? String ?? ""
                return speaker.map { "\($0): \(text)" } ?? text
            }.joined(separator: "\n")
        }
        if let text = json["transcript"] as? String { return text }
        throw MeetingSourceError.decode("no transcript field")
    }

    // MARK: - HTTP

    private func post(_ path: String, body: [String: Any], allowKeychainPrompt: Bool) async throws -> [String: Any] {
        let token = try tokenStore.accessToken(allowKeychainPrompt: allowKeychainPrompt)

        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Client gate — without these the API returns "Unsupported client".
        request.setValue("Granola/\(clientVersion) Electron/33.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue(clientVersion, forHTTPHeaderField: "X-Client-Version")
        request.setValue("electron", forHTTPHeaderField: "X-Client-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            if code == 401 { throw MeetingSourceError.notAuthenticated }
            throw MeetingSourceError.http(code, message ?? String(decoding: data.prefix(200), as: UTF8.self))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MeetingSourceError.decode("top-level not an object")
        }
        return json
    }

    static func meetingRef(from doc: [String: Any]) -> MeetingRef? {
        guard let id = (doc["id"] ?? doc["document_id"]) as? String else { return nil }
        let title = doc["title"] as? String ?? "Untitled meeting"
        let endedAt = (doc["end_timestamp"] ?? doc["ended_at"] ?? doc["updated_at"])
            .flatMap { $0 as? String }
            .flatMap { ISO8601DateFormatter.withFractional.date(from: $0) ?? ISO8601DateFormatter.plain.date(from: $0) }
        return MeetingRef(id: id, title: title, endedAt: endedAt)
    }
}
