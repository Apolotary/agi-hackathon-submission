//
//  KeychainManager.swift
//  agiagiagi
//
//  Created for AGI - Mistral Hackathon 2026
//

import Foundation
import Security

struct KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.agiagiagi.keys"

    private init() {}

    func store(_ value: String, for key: String) {
        guard !value.isEmpty else {
            delete(key)
            return
        }
        let data = Data(value.utf8)

        // Delete existing first
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[Keychain] Store failed for \(key): \(status)")
        }
    }

    func load(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Migration: move from UserDefaults to Keychain (one-time)
    static func migrateFromUserDefaults() {
        let keys = ["mistral_api_key", "openai_api_key", "elevenlabs_api_key"]
        for key in keys {
            if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty {
                // Only migrate if not already in keychain
                if shared.load(key) == nil {
                    shared.store(value, for: key)
                    print("[Keychain] Migrated \(key) from UserDefaults")
                }
            }
        }
    }
}
