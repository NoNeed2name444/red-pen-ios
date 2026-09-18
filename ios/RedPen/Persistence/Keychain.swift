import Foundation
import Security

/// The smallest keychain wrapper that does the job.
///
/// A session token is a bearer token: whoever holds it is the account until it
/// expires. Keeping one in UserDefaults or in a JSON file beside the library
/// would put it in every unencrypted backup that file lands in, which is how
/// tokens leak. The keychain is the one place on the phone that is not backed
/// up in the clear.
///
/// `afterFirstUnlock` rather than `whenUnlocked`: the app has background audio
/// for lecture playback, and a token that cannot be read while the phone is
/// locked is a session that dies in a pocket. `ThisDeviceOnly` because a
/// session restored onto a second phone from a backup should not be a signed-in
/// session on both.
enum Keychain {

    static func set(_ data: Data, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.redpen.app",
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func data(for key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.redpen.app",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
        else { return nil }
        return item as? Data
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.redpen.app",
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: the one thing stored in it

    private static let sessionKey = "session"

    static func save(_ session: Session) {
        guard let data = try? JSONEncoder.redPen.encode(session) else { return }
        set(data, for: sessionKey)
    }

    static func session() -> Session? {
        guard let data = data(for: sessionKey) else { return nil }
        return try? JSONDecoder.redPen.decode(Session.self, from: data)
    }

    static func clearSession() { remove(sessionKey) }
}
