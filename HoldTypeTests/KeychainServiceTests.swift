//
//  KeychainServiceTests.swift
//  HoldTypeTests
//
//  Created by Codex on 6/21/26.
//

import Foundation
import Security
import Testing
@testable import HoldType

struct KeychainServiceTests {

    @Test func missingAPIKeyLoadsAsNil() throws {
        let service = makeService(client: FakeKeychainClient())

        #expect(try service.loadAPIKey() == nil)
    }

    @Test func savesTrimmedAPIKeyToConfiguredKeychainItem() throws {
        let client = FakeKeychainClient()
        let service = KeychainService(
            client: client,
            serviceName: "test.service",
            interactionPolicy: .allowUserInitiatedAuthentication
        )

        try service.saveAPIKey("  sk-test-value\n")

        #expect(
            client.storedText(
                service: "test.service",
                account: KeychainService.openAIAPIKeyAccountName
            ) == "sk-test-value"
        )
        #expect(try service.loadAPIKey() == "sk-test-value")
        #expect(client.updateCount == 1)
        #expect(client.saveCount == 1)
        #expect(client.loadCount == 1)
    }

    @Test func savingNewAPIKeyUpdatesStableItemWithoutCreatingAnotherItem() throws {
        let client = FakeKeychainClient()
        let service = makeService(client: client)

        try service.saveAPIKey("sk-old")
        try service.saveAPIKey("sk-new")

        #expect(try service.loadAPIKey() == "sk-new")
        #expect(
            client.storedText(
                service: KeychainService.defaultServiceName,
                account: KeychainService.openAIAPIKeyAccountName
            ) == "sk-new"
        )
        #expect(client.itemCount == 1)
        #expect(client.updateCount == 2)
        #expect(client.saveCount == 1)
        #expect(client.loadCount == 2)
    }

    @Test func rejectsBlankAPIKeyWithoutWritingSecretData() {
        let client = FakeKeychainClient()
        let service = makeService(client: client)

        #expect(throws: KeychainServiceError.emptyAPIKey) {
            try service.saveAPIKey(" \n\t ")
        }
        #expect(client.saveCount == 0)
        #expect(client.updateCount == 0)
        #expect(client.isEmpty)
    }

    @Test func deletesSavedAPIKeyAndTreatsMissingItemAsSuccess() throws {
        let client = FakeKeychainClient()
        let service = makeService(client: client)

        try service.saveAPIKey("sk-test")
        try service.deleteAPIKey()
        try service.deleteAPIKey()

        #expect(try service.loadAPIKey() == nil)
        #expect(client.deleteCount == 2)
    }

    @Test func invalidStoredSecretDataThrowsControlledError() throws {
        let client = FakeKeychainClient()
        client.seed(
            Data([0xff]),
            service: KeychainService.defaultServiceName,
            account: KeychainService.openAIAPIKeyAccountName
        )
        let service = makeService(client: client)

        #expect(throws: KeychainServiceError.invalidStoredAPIKey) {
            _ = try service.loadAPIKey()
        }
    }

    @Test func apiKeyAvailabilityChecksNonInteractiveReadWithoutPromptingLoad() throws {
        let client = FakeKeychainClient()
        let service = makeService(client: client)

        #expect(try service.apiKeyAvailability() == .missing)
        #expect(client.nonInteractiveLoadCount == 1)
        #expect(client.loadCount == 0)

        try service.saveAPIKey("sk-test")
        let interactiveLoadCountAfterSave = client.loadCount

        #expect(try service.apiKeyAvailability() == .saved)
        #expect(client.nonInteractiveLoadCount == 2)
        #expect(client.loadCount == interactiveLoadCountAfterSave)
    }

    @Test func apiKeyAvailabilityReportsUnavailableForNonInteractiveReadDenial() throws {
        let client = FakeKeychainClient(nonInteractiveLoadError: errSecInteractionNotAllowed)
        let service = makeService(client: client)

        #expect(
            try service.apiKeyAvailability()
                == .unavailable(KeychainService.inaccessibleAPIKeyMessage)
        )
        #expect(client.nonInteractiveLoadCount == 1)
        #expect(client.loadCount == 0)
    }

    @Test func xctestEnvironmentDefaultsToNonInteractivePolicy() {
        #expect(
            KeychainInteractionPolicy.currentProcessDefault(
                environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
            ) == .disallowAuthenticationUI
        )
        #expect(
            KeychainInteractionPolicy.currentProcessDefault(
                environment: ["XCTestSessionIdentifier": "test-session"]
            ) == .disallowAuthenticationUI
        )
        #expect(
            KeychainInteractionPolicy.currentProcessDefault(
                environment: ["XCTestBundlePath": "/tmp/HoldTypeTests.xctest"]
            ) == .disallowAuthenticationUI
        )
        #expect(
            KeychainInteractionPolicy.currentProcessDefault(
                environment: ["XCInjectBundle": "/tmp/HoldTypeUITests.xctest"]
            ) == .disallowAuthenticationUI
        )
    }

    @Test func automationEnvironmentDisablesLiveKeychainAccess() {
        #expect(
            KeychainInteractionPolicy.currentProcessDefault(
                environment: [KeychainInteractionPolicy.automationEnvironmentKey: "1"]
            ) == .disableKeychainAccess
        )
        #expect(
            KeychainInteractionPolicy.currentProcessDefault(
                environment: [KeychainInteractionPolicy.automationEnvironmentKey: "true"]
            ) == .disableKeychainAccess
        )
    }

    @Test func authenticationUISkipEnvironmentDefaultsToNonInteractivePolicy() {
        #expect(
            KeychainInteractionPolicy.currentProcessDefault(
                environment: [
                    KeychainInteractionPolicy.authenticationUIEnvironmentKey:
                        KeychainInteractionPolicy.skipAuthenticationUIValue
                ]
            ) == .disallowAuthenticationUI
        )
    }

    @Test func nonXCTestEnvironmentKeepsUserInitiatedAuthenticationPolicy() {
        #expect(
            KeychainInteractionPolicy.currentProcessDefault(environment: [:])
                == .allowUserInitiatedAuthentication
        )
    }

    @Test func nonInteractivePolicySavesAndValidatesWithoutPromptingLoad() throws {
        let client = FakeKeychainClient()
        let service = makeService(client: client, interactionPolicy: .disallowAuthenticationUI)

        try service.saveAPIKey("sk-test")

        #expect(client.updateAuthenticationUIs == [.skip])
        #expect(client.saveAuthenticationUIs == [.skip])
        #expect(client.loadAuthenticationUIs == [.skip])
        #expect(client.loadCount == 0)
        #expect(client.nonInteractiveLoadCount == 1)
        #expect(try service.loadAPIKey() == "sk-test")
    }

    @Test func automationPolicyDoesNotTouchKeychainClient() throws {
        let client = FakeKeychainClient()
        client.seed(
            Data("sk-test".utf8),
            service: KeychainService.defaultServiceName,
            account: KeychainService.openAIAPIKeyAccountName
        )
        let service = makeService(client: client, interactionPolicy: .disableKeychainAccess)

        #expect(try service.loadAPIKey() == nil)
        #expect(try service.apiKeyAvailability() == .missing)
        #expect(throws: KeychainServiceError.automationKeychainAccessDisabled) {
            try service.saveAPIKey("sk-new")
        }
        #expect(throws: KeychainServiceError.automationKeychainAccessDisabled) {
            try service.deleteAPIKey()
        }
        #expect(client.saveCount == 0)
        #expect(client.updateCount == 0)
        #expect(client.loadCount == 0)
        #expect(client.nonInteractiveLoadCount == 0)
        #expect(client.deleteCount == 0)
    }

}

private func makeService(
    client: FakeKeychainClient,
    interactionPolicy: KeychainInteractionPolicy = .allowUserInitiatedAuthentication
) -> KeychainService {
    KeychainService(client: client, interactionPolicy: interactionPolicy)
}

private final class FakeKeychainClient: KeychainClient {
    private struct Key: Hashable {
        let service: String
        let account: String
    }

    private var storedData: [Key: Data] = [:]
    private(set) var saveCount = 0
    private(set) var updateCount = 0
    private(set) var loadCount = 0
    private(set) var nonInteractiveLoadCount = 0
    private(set) var deleteCount = 0
    private(set) var saveAuthenticationUIs: [KeychainAuthenticationUI] = []
    private(set) var updateAuthenticationUIs: [KeychainAuthenticationUI] = []
    private(set) var loadAuthenticationUIs: [KeychainAuthenticationUI] = []
    private let nonInteractiveLoadError: OSStatus?

    init(
        nonInteractiveLoadError: OSStatus? = nil
    ) {
        self.nonInteractiveLoadError = nonInteractiveLoadError
    }

    var isEmpty: Bool {
        storedData.isEmpty
    }

    var itemCount: Int {
        storedData.count
    }

    func saveGenericPassword(
        _ data: Data,
        service: String,
        account: String,
        authenticationUI: KeychainAuthenticationUI
    ) throws {
        saveCount += 1
        saveAuthenticationUIs.append(authenticationUI)
        storedData[Key(service: service, account: account)] = data
    }

    func updateGenericPassword(
        _ data: Data,
        service: String,
        account: String,
        authenticationUI: KeychainAuthenticationUI
    ) throws {
        updateCount += 1
        updateAuthenticationUIs.append(authenticationUI)
        let key = Key(service: service, account: account)
        guard storedData[key] != nil else {
            throw KeychainServiceError.unhandledKeychainStatus(errSecItemNotFound)
        }

        storedData[key] = data
    }

    func loadGenericPassword(
        service: String,
        account: String,
        authenticationUI: KeychainAuthenticationUI
    ) throws -> Data? {
        loadAuthenticationUIs.append(authenticationUI)
        if authenticationUI == .skip {
            nonInteractiveLoadCount += 1
        } else {
            loadCount += 1
        }
        if authenticationUI == .skip, let nonInteractiveLoadError {
            throw KeychainServiceError.unhandledKeychainStatus(nonInteractiveLoadError)
        }

        return storedData[Key(service: service, account: account)]
    }

    func deleteGenericPassword(service: String, account: String) throws {
        deleteCount += 1
        storedData.removeValue(forKey: Key(service: service, account: account))
    }

    func seed(_ data: Data, service: String, account: String) {
        storedData[Key(service: service, account: account)] = data
    }

    func storedText(service: String, account: String) -> String? {
        storedData[Key(service: service, account: account)].flatMap {
            String(data: $0, encoding: .utf8)
        }
    }
}
