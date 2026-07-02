import XCTest
import CryptoKit
@testable import JoshuWidgets

final class GranolaTokenStoreTests: XCTestCase {
    /// Round-trip through the exact OSCrypt scheme (PBKDF2-SHA1/saltysalt/1003,
    /// AES-128-CBC, v10 prefix, 16-space IV) using a known password, encrypting
    /// with the same derived key and asserting decrypt recovers the plaintext.
    func testOSCryptDecryptRoundTrip() throws {
        let password = Data("hunter2-random-keychain-pw".utf8)
        let key = GranolaTokenStore.deriveOSCryptKey(password: password)
        let plaintext = Data(#"{"workos_tokens":"{\"access_token\":\"abc.def.ghi\"}"}"#.utf8)

        let blob = try encryptOSCrypt(plaintext: plaintext, key: key)
        let recovered = try GranolaTokenStore.oscryptDecrypt(blob: blob, key: key)
        XCTAssertEqual(recovered, plaintext)

        // And the token extraction understands the nested-JSON-string shape.
        let object = try JSONSerialization.jsonObject(with: recovered) as! [String: Any]
        XCTAssertEqual(GranolaTokenStore.workosAccessToken(from: object), "abc.def.ghi")
    }

    func testRejectsNonV10Blob() {
        let key = GranolaTokenStore.deriveOSCryptKey(password: Data("x".utf8))
        XCTAssertThrowsError(try GranolaTokenStore.oscryptDecrypt(blob: Data("nope".utf8), key: key))
    }

    func testExpiryDetection() {
        // exp in the past.
        let past = makeJWT(exp: Date(timeIntervalSince1970: 1_000_000))
        XCTAssertTrue(GranolaTokenStore.isExpired(past))
        // exp far in the future.
        let future = makeJWT(exp: Date(timeIntervalSinceNow: 86_400))
        XCTAssertFalse(GranolaTokenStore.isExpired(future))
        XCTAssertTrue(GranolaTokenStore.isExpired("garbage"))
    }

    // Helpers

    private func makeJWT(exp: Date) -> String {
        func b64(_ dict: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: dict)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(b64(["alg": "RS256"])).\(b64(["exp": exp.timeIntervalSince1970])).sig"
    }

    private func encryptOSCrypt(plaintext: Data, key: SymmetricKey) throws -> Data {
        // Mirror of oscryptDecrypt for test fixtures.
        let iv = [UInt8](repeating: 0x20, count: 16)
        let keyBytes = key.withUnsafeBytes { [UInt8]($0) }
        let input = [UInt8](plaintext)
        var out = [UInt8](repeating: 0, count: input.count + 16)
        var moved = 0
        let status = CCCrypt(
            CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
            keyBytes, keyBytes.count, iv, input, input.count, &out, out.count, &moved)
        XCTAssertEqual(Int(status), kCCSuccess)
        return Data("v10".utf8) + Data(out.prefix(moved))
    }
}

import CommonCrypto

final class ActionItemExtractorTests: XCTestCase {
    func testParsesStructuredOutputEnvelope() {
        let envelope = #"{"type":"result","result":"ignored","structured_output":{"actionItems":[{"text":"ship it","isImmediate":true,"suggestedPrompt":"run tests","owner":"jen"}]}}"#
        let items = ActionItemExtractor.parse(claudeEnvelope: Data(envelope.utf8))
        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(items?.first?.text, "ship it")
        XCTAssertTrue(items?.first?.isImmediate ?? false)
        XCTAssertEqual(items?.first?.suggestedPrompt, "run tests")
    }

    func testParsesResultStringJSON() {
        let inner = #"{\"actionItems\":[{\"text\":\"email bob\",\"isImmediate\":false}]}"#
        let envelope = "{\"result\":\"\(inner)\"}"
        let items = ActionItemExtractor.parse(claudeEnvelope: Data(envelope.utf8))
        XCTAssertEqual(items?.first?.text, "email bob")
        XCTAssertFalse(items?.first?.isImmediate ?? true)
        XCTAssertNil(items?.first?.owner)
    }

    func testParsesFencedFromRawText() {
        let text = "Here you go:\n```json\n{\"actionItems\":[{\"text\":\"deploy\",\"isImmediate\":true}]}\n```"
        let items = ActionItemExtractor.parseActionItems(text: text)
        XCTAssertEqual(items?.first?.text, "deploy")
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(ActionItemExtractor.parseActionItems(text: "no items here"))
    }
}

final class MeetingStoreTests: XCTestCase {
    func testDedupeAcrossProcessing() throws {
        let store = try MeetingStore()
        XCTAssertFalse(try store.isProcessed("doc-1"))

        let items = [ActionItem(text: "t", owner: nil, isImmediate: true, suggestedPrompt: nil)]
        try store.markProcessed(ProcessedMeeting(
            id: "doc-1", title: "Standup", processedAt: Date(),
            actionItemsJSON: try JSONEncoder().encode(items)))

        XCTAssertTrue(try store.isProcessed("doc-1"))
        XCTAssertEqual(try store.recent().count, 1)
        XCTAssertEqual(try store.recent().first?.actionItems.first?.text, "t")

        // Re-marking the same id doesn't duplicate.
        try store.markProcessed(ProcessedMeeting(
            id: "doc-1", title: "Standup", processedAt: Date(), actionItemsJSON: Data("[]".utf8)))
        XCTAssertEqual(try store.recent().count, 1)
    }
}

final class GranolaSourceParsingTests: XCTestCase {
    func testMeetingRefRequiresEndTimestamp() {
        let withEnd = GranolaSource.meetingRef(from: [
            "id": "d1", "title": "Sync", "end_timestamp": "2026-07-01T10:00:00.000Z",
        ])
        XCTAssertEqual(withEnd?.id, "d1")
        XCTAssertNotNil(withEnd?.endedAt)

        let noEnd = GranolaSource.meetingRef(from: ["id": "d2", "title": "Draft"])
        XCTAssertNotNil(noEnd) // parsed, but endedAt nil → filtered by caller
        XCTAssertNil(noEnd?.endedAt)
    }
}
