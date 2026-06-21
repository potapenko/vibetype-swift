//
//  KeychainService.swift
//  vibetype
//
//  Created by Codex on 6/21/26.
//

import Foundation
import Security

protocol APIKeyStorage {
    func saveAPIKey(_ apiKey: String) throws
    func loadAPIKey() throws -> String?
    func deleteAPIKey() throws
}

protocol KeychainClient {
    func saveGenericPassword(_ data: Data, service: String, account: String) throws
    func loadGenericPassword(service: String, account: String) throws -> Data?
    func deleteGenericPassword(service: String, account: String) throws
}

struct KeychainService: APIKeyStorage {
    static let defaultServiceName = "com.potapenko.vibetype.openai"
    static let openAIAPIKeyAccount = "openai-api-key"

    private let client: KeychainClient
    private let serviceName: String
    private let accountName: String

    init(
        client: KeychainClient = SystemKeychainClient(),
        serviceName: String = Self.defaultServiceName,
        accountName: String = Self.openAIAPIKeyAccount
    ) {
        self.client = client
        self.serviceName = serviceName
        self.accountName = accountName
    }

    func saveAPIKey(_ apiKey: String) throws {
        let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAPIKey.isEmpty else {
            throw KeychainServiceError.emptyAPIKey
        }

        try client.saveGenericPassword(
            Data(normalizedAPIKey.utf8),
            service: serviceName,
            account: accountName
        )
    }

    func loadAPIKey() throws -> String? {
        guard let data = try client.loadGenericPassword(
            service: serviceName,
            account: accountName
        ) else {
            return nil
        }

        guard let apiKey = String(data: data, encoding: .utf8), !apiKey.isEmpty else {
            throw KeychainServiceError.invalidStoredAPIKey
        }

        return apiKey
    }

    func deleteAPIKey() throws {
        try client.deleteGenericPassword(service: serviceName, account: accountName)
    }
}

struct SystemKeychainClient: KeychainClient {
    func saveGenericPassword(_ data: Data, service: String, account: String) throws {
        var addQuery = baseQuery(service: service, account: account)
        addQuery[kSecValueData as String] = data

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            try updateGenericPassword(data, service: service, account: account)
        default:
            throw KeychainServiceError.unhandledKeychainStatus(addStatus)
        }
    }

    func loadGenericPassword(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainServiceError.invalidStoredAPIKey
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainServiceError.unhandledKeychainStatus(status)
        }
    }

    func deleteGenericPassword(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.unhandledKeychainStatus(status)
        }
    }

    private func updateGenericPassword(_ data: Data, service: String, account: String) throws {
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(
            baseQuery(service: service, account: account) as CFDictionary,
            attributes as CFDictionary
        )

        guard status == errSecSuccess else {
            throw KeychainServiceError.unhandledKeychainStatus(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }
}

enum KeychainServiceError: Error, Equatable, LocalizedError {
    case emptyAPIKey
    case invalidStoredAPIKey
    case unhandledKeychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "Enter an OpenAI API key before saving."
        case .invalidStoredAPIKey:
            return "The saved OpenAI API key could not be read."
        case .unhandledKeychainStatus:
            return "The OpenAI API key could not be saved in Keychain."
        }
    }
}
