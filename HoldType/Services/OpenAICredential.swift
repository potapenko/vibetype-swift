//
//  OpenAICredential.swift
//  HoldType
//
//  Created by Codex on 7/7/26.
//

import Foundation
import HoldTypeOpenAI

typealias OpenAICredential = HoldTypeOpenAI.OpenAICredential
typealias OpenAICredentialResolving = HoldTypeOpenAI.OpenAICredentialResolving

struct OpenAICredentialResolver: OpenAICredentialResolving {
    private let apiKeyStorage: any APIKeyStorage

    init(apiKeyStorage: any APIKeyStorage = APIKeyCredentialProvider.shared) {
        self.apiKeyStorage = apiKeyStorage
    }

    func resolveOpenAICredential() throws -> OpenAICredential {
        do {
            guard let apiKey = try apiKeyStorage.loadAPIKey() else {
                throw OpenAICredentialResolutionError.missingAPIKey
            }

            return try OpenAICredential(apiKey: apiKey)
        } catch let error as OpenAICredentialResolutionError {
            throw error
        } catch OpenAICredential.ValidationError.missingAPIKey {
            throw OpenAICredentialResolutionError.missingAPIKey
        } catch {
            throw OpenAICredentialResolutionError.apiKeyUnavailable(Self.unavailableMessage(for: error))
        }
    }

    private static func unavailableMessage(for error: Error) -> String {
        if let error = error as? KeychainServiceError,
           case .unhandledKeychainStatus(let status) = error,
           KeychainService.isPermissionDeniedStatus(status) {
            return KeychainService.inaccessibleAPIKeyMessage
        }

        return error.localizedDescription
    }
}

enum OpenAICredentialResolutionError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case apiKeyUnavailable(String)

    var availability: APIKeyAvailability {
        switch self {
        case .missingAPIKey:
            return .missing
        case .apiKeyUnavailable(let message):
            return .unavailable(message)
        }
    }

    var errorDescription: String? {
        availability.settingsDescription
    }

    var transcriptionServiceError: OpenAITranscriptionServiceError {
        switch self {
        case .missingAPIKey:
            return .missingAPIKey
        case .apiKeyUnavailable:
            return .apiKeyUnavailable
        }
    }
}
