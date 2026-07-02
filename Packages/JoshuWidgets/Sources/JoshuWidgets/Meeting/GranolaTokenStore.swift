import Foundation
import CryptoKit
import Security
import CommonCrypto

/// Reads the WorkOS access token Granola stores locally (M8a decision A2).
/// Prefers the plaintext supabase.json if it holds an unexpired token
/// (no Keychain prompt); otherwise decrypts supabase.json.enc via the
/// Electron safeStorage / Chromium OSCrypt scheme.
public struct GranolaTokenStore: Sendable {
    public static let granolaDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Granola")

    public init() {}

    /// - Parameter allowKeychainPrompt: when false, only the no-prompt
    ///   plaintext path is tried (background polling); when true, the
    ///   encrypted path may trigger a one-time Keychain access prompt
    ///   (explicit user "Connect" action).
    public func accessToken(allowKeychainPrompt: Bool) throws -> String {
        guard FileManager.default.fileExists(atPath: Self.granolaDir.path) else {
            throw MeetingSourceError.granolaNotInstalled
        }
        if let token = plaintextToken(), !Self.isExpired(token) {
            return token
        }
        guard allowKeychainPrompt else {
            throw MeetingSourceError.needsConnect
        }
        if let token = try decryptedToken(), !Self.isExpired(token) {
            return token
        }
        throw MeetingSourceError.notAuthenticated
    }

    // MARK: - Plaintext (older installs)

    private func plaintextToken() -> String? {
        let url = Self.granolaDir.appendingPathComponent("supabase.json")
        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return Self.workosAccessToken(from: object)
    }

    // MARK: - Encrypted (current installs)

    private func decryptedToken() throws -> String? {
        let encURL = Self.granolaDir.appendingPathComponent("supabase.json.enc")
        guard let blob = try? Data(contentsOf: encURL) else { return nil }

        let password = try keychainPassword()
        let key = Self.deriveOSCryptKey(password: password)

        let plaintext = try Self.oscryptDecrypt(blob: blob, key: key)
        guard let object = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any]
        else {
            throw MeetingSourceError.decode("supabase.json.enc did not decrypt to JSON — " +
                "may need the storage.dek two-step (see docs/integrations/granola.md)")
        }
        return Self.workosAccessToken(from: object)
    }

    /// Triggers a one-time Keychain access prompt the first time.
    private func keychainPassword() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Granola Safe Storage",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw MeetingSourceError.tokenUnavailable("Keychain status \(status)")
        }
        return data
    }

    // MARK: - Crypto (Chromium OSCrypt / Electron safeStorage, macOS)

    static func deriveOSCryptKey(password: Data) -> SymmetricKey {
        // PBKDF2-HMAC-SHA1, salt "saltysalt", 1003 iterations, 16-byte key.
        let salt = Data("saltysalt".utf8)
        var derived = [UInt8](repeating: 0, count: 16)
        password.withUnsafeBytes { pwPtr in
            salt.withUnsafeBytes { saltPtr in
                _ = CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwPtr.baseAddress, password.count,
                    saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                    &derived, derived.count)
            }
        }
        return SymmetricKey(data: Data(derived))
    }

    /// `b"v10"` prefix + AES-128-CBC, IV = 16 spaces, PKCS7 padding.
    static func oscryptDecrypt(blob: Data, key: SymmetricKey) throws -> Data {
        guard blob.count > 3, blob.prefix(3) == Data("v10".utf8) else {
            throw MeetingSourceError.decode("not a v10 safeStorage blob")
        }
        let ciphertext = [UInt8](blob.dropFirst(3))
        let iv = [UInt8](repeating: 0x20, count: 16)
        let keyBytes = key.withUnsafeBytes { [UInt8]($0) }

        var out = [UInt8](repeating: 0, count: ciphertext.count + 16)
        var moved = 0
        let status = CCCrypt(
            CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
            keyBytes, keyBytes.count, iv,
            ciphertext, ciphertext.count,
            &out, out.count, &moved)
        guard status == kCCSuccess else {
            throw MeetingSourceError.decode("AES-CBC failed (\(status))")
        }
        return Data(out.prefix(moved))
    }

    // MARK: - Shared helpers

    static func workosAccessToken(from object: [String: Any]) -> String? {
        // workos_tokens is a JSON *string* holding {access_token, refresh_token}.
        if let raw = object["workos_tokens"] as? String,
           let data = raw.data(using: .utf8),
           let tokens = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return tokens["access_token"] as? String
        }
        if let tokens = object["workos_tokens"] as? [String: Any] {
            return tokens["access_token"] as? String
        }
        return nil
    }

    static func isExpired(_ jwt: String) -> Bool {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return true }
        var payload = String(parts[1])
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard
            let data = Data(base64Encoded: payload.replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")),
            let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let exp = claims["exp"] as? Double
        else { return true }
        return exp < Date().timeIntervalSince1970
    }
}
