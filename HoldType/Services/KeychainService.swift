//
//  KeychainService.swift
//  HoldType
//
//  Created by Codex on 6/21/26.
//

import Foundation
import Security

protocol APIKeyStorage {
    func saveAPIKey(_ apiKey: String) throws
    func loadAPIKey() throws -> String?
    func loadAPIKeyWithoutUI() throws -> String?
    func deleteAPIKey() throws
    func apiKeyAvailability() throws -> APIKeyAvailability
}

extension APIKeyStorage {
    func loadAPIKeyWithoutUI() throws -> String? {
        try loadAPIKey()
    }

    func apiKeyAvailability() throws -> APIKeyAvailability {
        guard let apiKey = try loadAPIKeyWithoutUI()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            return .missing
        }

        return .saved
    }
}

enum KeychainInteractionPolicy: Equatable {
    case allowUserInitiatedAuthentication
    case disallowAuthenticationUI
    case disableKeychainAccess

    static let automationEnvironmentKey = "HOLDTYPE_AUTOMATION"
    static let authenticationUIEnvironmentKey = "HOLDTYPE_KEYCHAIN_AUTHENTICATION_UI"
    static let skipAuthenticationUIValue = "skip"

    static func currentProcessDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> KeychainInteractionPolicy {
        if shouldDisableKeychainAccess(environment: environment) {
            return .disableKeychainAccess
        }

        if shouldDisallowAuthenticationUI(environment: environment) || isRunningXCTest(environment: environment) {
            return .disallowAuthenticationUI
        }

        return .allowUserInitiatedAuthentication
    }

    private static func shouldDisableKeychainAccess(environment: [String: String]) -> Bool {
        isEnabled(environment[automationEnvironmentKey])
    }

    private static func shouldDisallowAuthenticationUI(environment: [String: String]) -> Bool {
        return environment[authenticationUIEnvironmentKey]?.lowercased() == skipAuthenticationUIValue
    }

    private static func isRunningXCTest(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCInjectBundle"] != nil
            || environment["XCInjectBundleInto"] != nil
    }

    private static func isEnabled(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        switch value.lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }
}

enum KeychainAuthenticationUI: Equatable {
    case allow
    case skip

    var secItemValue: CFString {
        switch self {
        case .allow:
            return kSecUseAuthenticationUIAllow
        case .skip:
            return kSecUseAuthenticationUISkip
        }
    }
}

protocol KeychainClient {
    func saveGenericPassword(
        _ data: Data,
        service: String,
        account: String,
        authenticationUI: KeychainAuthenticationUI
    ) throws

    func updateGenericPassword(
        _ data: Data,
        service: String,
        account: String,
        authenticationUI: KeychainAuthenticationUI
    ) throws

    func loadGenericPassword(
        service: String,
        account: String,
        authenticationUI: KeychainAuthenticationUI
    ) throws -> Data?

    func deleteGenericPassword(service: String, account: String) throws
}

extension KeychainClient {
    func loadGenericPasswordWithoutUI(service: String, account: String) throws -> Data? {
        try loadGenericPassword(service: service, account: account, authenticationUI: .skip)
    }
}

struct KeychainService: APIKeyStorage {
    static let defaultServiceName = "HoldType OpenAI API Key"
    static let openAIAPIKeyAccountName = "openai-api-key"
    static let inaccessibleAPIKeyMessage = "The saved OpenAI API key is unavailable. Paste the API key again."

    private let client: KeychainClient
    private let serviceName: String
    private let interactionPolicy: KeychainInteractionPolicy

    init(
        client: KeychainClient = SystemKeychainClient(),
        serviceName: String = Self.defaultServiceName,
        interactionPolicy: KeychainInteractionPolicy = .currentProcessDefault()
    ) {
        self.client = client
        self.serviceName = serviceName
        self.interactionPolicy = interactionPolicy
    }

    func saveAPIKey(_ apiKey: String) throws {
        let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAPIKey.isEmpty else {
            throw KeychainServiceError.emptyAPIKey
        }
        guard interactionPolicy != .disableKeychainAccess else {
            throw KeychainServiceError.automationKeychainAccessDisabled
        }

        try saveStableKeychainItem(Data(normalizedAPIKey.utf8))
    }

    func loadAPIKey() throws -> String? {
        try loadAPIKeyWithoutUI()
    }

    func loadAPIKeyWithoutUI() throws -> String? {
        guard interactionPolicy != .disableKeychainAccess else {
            return nil
        }

        guard let data = try client.loadGenericPasswordWithoutUI(
            service: serviceName,
            account: Self.openAIAPIKeyAccountName
        ) else {
            return nil
        }

        return try Self.apiKey(from: data)
    }

    func deleteAPIKey() throws {
        guard interactionPolicy != .disableKeychainAccess else {
            throw KeychainServiceError.automationKeychainAccessDisabled
        }

        try client.deleteGenericPassword(
            service: serviceName,
            account: Self.openAIAPIKeyAccountName
        )
    }

    func apiKeyAvailability() throws -> APIKeyAvailability {
        do {
            guard let apiKey = try loadAPIKeyWithoutUI()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !apiKey.isEmpty else {
                return .missing
            }

            return .saved
        } catch let error as KeychainServiceError {
            if case .unhandledKeychainStatus(let status) = error,
               Self.isPermissionDeniedStatus(status) {
                return .unavailable(Self.inaccessibleAPIKeyMessage)
            }

            throw error
        }
    }

    private func saveStableKeychainItem(_ data: Data) throws {
        let authenticationUI = authenticationUIForCurrentPolicy()
        do {
            try client.updateGenericPassword(
                data,
                service: serviceName,
                account: Self.openAIAPIKeyAccountName,
                authenticationUI: authenticationUI
            )
        } catch let error as KeychainServiceError {
            if case .unhandledKeychainStatus(let status) = error,
               status == errSecItemNotFound {
                do {
                    try client.saveGenericPassword(
                        data,
                        service: serviceName,
                        account: Self.openAIAPIKeyAccountName,
                        authenticationUI: authenticationUI
                    )
                } catch let addError as KeychainServiceError {
                    if case .unhandledKeychainStatus(let addStatus) = addError,
                       addStatus == errSecDuplicateItem {
                        try client.updateGenericPassword(
                            data,
                            service: serviceName,
                            account: Self.openAIAPIKeyAccountName,
                            authenticationUI: authenticationUI
                        )
                    } else {
                        throw addError
                    }
                }
                try validateAccess(authenticationUI: authenticationUI)
                return
            }

            throw error
        }

        try validateAccess(authenticationUI: authenticationUI)
    }

    private func authenticationUIForCurrentPolicy() -> KeychainAuthenticationUI {
        switch interactionPolicy {
        case .allowUserInitiatedAuthentication:
            return .allow
        case .disallowAuthenticationUI, .disableKeychainAccess:
            return .skip
        }
    }

    private func validateAccess(authenticationUI: KeychainAuthenticationUI) throws {
        guard let data = try client.loadGenericPassword(
            service: serviceName,
            account: Self.openAIAPIKeyAccountName,
            authenticationUI: authenticationUI
        ) else {
            throw KeychainServiceError.invalidStoredAPIKey
        }

        _ = try Self.apiKey(from: data)
    }

    private static func apiKey(from data: Data) throws -> String {
        guard let apiKey = String(data: data, encoding: .utf8), !apiKey.isEmpty else {
            throw KeychainServiceError.invalidStoredAPIKey
        }

        return apiKey
    }

    static func isPermissionDeniedStatus(_ status: OSStatus) -> Bool {
        status == errSecAuthFailed
            || status == errSecUserCanceled
            || status == errSecInteractionNotAllowed
    }
}

struct SystemKeychainClient: KeychainClient {
    func saveGenericPassword(
        _ data: Data,
        service: String,
        account: String,
        authenticationUI: KeychainAuthenticationUI
    ) throws {
        var addQuery = baseQuery(service: service, account: account)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrLabel as String] = service
        addQuery[kSecUseAuthenticationUI as String] = authenticationUI.secItemValue

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        default:
            throw KeychainServiceError.unhandledKeychainStatus(addStatus)
        }
    }

    func updateGenericPassword(
        _ data: Data,
        service: String,
        account: String,
        authenticationUI: KeychainAuthenticationUI
    ) throws {
        var query = baseQuery(service: service, account: account)
        query[kSecUseAuthenticationUI as String] = authenticationUI.secItemValue

        let attributesToUpdate = [
            kSecValueData as String: data,
            kSecAttrLabel as String: service,
        ] as [String: Any]

        let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        guard status == errSecSuccess else {
            throw KeychainServiceError.unhandledKeychainStatus(status)
        }
    }

    func loadGenericPassword(
        service: String,
        account: String,
        authenticationUI: KeychainAuthenticationUI
    ) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = authenticationUI.secItemValue

        return try copyGenericPasswordData(query: query)
    }

    func deleteGenericPassword(service: String, account: String) throws {
        var query = baseQuery(service: service, account: account)
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
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

    private func copyGenericPasswordData(query: [String: Any]) throws -> Data? {
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
}

enum KeychainServiceError: Error, Equatable, LocalizedError {
    case emptyAPIKey
    case invalidStoredAPIKey
    case automationKeychainAccessDisabled
    case unhandledKeychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "Enter an OpenAI API key."
        case .invalidStoredAPIKey:
            return "The saved OpenAI API key could not be read."
        case .automationKeychainAccessDisabled:
            return "OpenAI API key storage is disabled during automated testing."
        case .unhandledKeychainStatus:
            return "The OpenAI API key could not be saved in Keychain."
        }
    }
}
