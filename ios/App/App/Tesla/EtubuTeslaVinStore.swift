import Foundation
import Security

/// VIN storage — Keychain so pairing survives app relaunch (UserDefaults wipe does not clear it).
enum EtubuTeslaVinStore {
    private static let service = "com.etubu.app.teslaVIN"
    private static let account = "vehicleVIN"
    private static let pairedPrefix = "pairedConfirmed."
    private static var memoryCache: String?

    static var vin: String? {
        get {
            if let cached = normalizeOptional(memoryCache) { return cached }
            let loaded = loadFromKeychain()
            memoryCache = loaded
            return normalizeOptional(loaded)
        }
        set {
            if let newValue {
                let cleaned = normalize(newValue)
                memoryCache = cleaned
                saveToKeychain(cleaned)
                rememberRecent(cleaned)
            } else {
                memoryCache = nil
                deleteFromKeychain()
            }
        }
    }

    static func isValidVIN(_ value: String) -> Bool {
        normalize(value).count == 17
    }

    static func normalize(_ value: String) -> String {
        value.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    static func pairedConfirmed(for vin: String) -> Bool {
        let key = pairedPrefix + normalize(vin)
        return UserDefaults.standard.bool(forKey: key)
    }

    static func setPairedConfirmed(_ confirmed: Bool, for vin: String) {
        let key = pairedPrefix + normalize(vin)
        UserDefaults.standard.set(confirmed, forKey: key)
    }

    private static let recentsKey = "etubu.vin.recents"
    private static let maxRecents = 6

    /// Last-used VINs (current first), for switching cars without retyping.
    static var recents: [String] {
        let raw = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        var seen = Set<String>()
        var out: [String] = []
        if let current = vin {
            seen.insert(current)
            out.append(current)
        }
        for item in raw {
            let v = normalize(item)
            guard isValidVIN(v), !seen.contains(v) else { continue }
            seen.insert(v)
            out.append(v)
            if out.count >= maxRecents { break }
        }
        return out
    }

    static func rememberRecent(_ vin: String) {
        let v = normalize(vin)
        guard isValidVIN(v) else { return }
        var list = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        list.removeAll { normalize($0) == v }
        list.insert(v, at: 0)
        if list.count > maxRecents { list = Array(list.prefix(maxRecents)) }
        UserDefaults.standard.set(list, forKey: recentsKey)
    }

    private static func normalizeOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = normalize(value)
        return cleaned.count == 17 ? cleaned : nil
    }

    private static func saveToKeychain(_ vin: String) {
        let data = Data(vin.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private static func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
