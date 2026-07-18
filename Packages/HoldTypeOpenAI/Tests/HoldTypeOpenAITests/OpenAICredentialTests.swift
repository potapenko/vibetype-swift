import Testing
@testable import HoldTypeOpenAI

struct OpenAICredentialTests {
    @Test func trimsOnlySurroundingWhitespaceAndUsesTheCompatibilitySource() throws {
        let credential = try OpenAICredential(apiKey: "  Sk-Test Key\tValue \n")

        #expect(credential.apiKey == "Sk-Test Key\tValue")
        #expect(credential.source == .runtimeStorage)
    }

    @Test func rejectsEmptyNormalizedKeysWithATypedValidationError() {
        for apiKey in ["", " \n\t "] {
            #expect(throws: OpenAICredential.ValidationError.missingAPIKey) {
                _ = try OpenAICredential(apiKey: apiKey)
            }
        }
    }

    @Test func equalityIncludesTheNormalizedKeyAndSource() throws {
        let credential = try OpenAICredential(apiKey: "sk-test")

        #expect(credential == (try OpenAICredential(apiKey: " sk-test ")))
        #expect(credential != (try OpenAICredential(apiKey: "SK-TEST")))
    }

    @Test func publicValuesAreSendableButNotTransportContracts() throws {
        requireSendable(OpenAICredential.self)
        requireSendable(OpenAICredentialSource.self)

        let credential = try OpenAICredential(apiKey: "sk-non-codable")
        #expect(((credential as Any) is any Encodable) == false)
        #expect(((credential as Any) is any Decodable) == false)
        #expect(((credential.source as Any) is any Encodable) == false)
        #expect(((credential.source as Any) is any Decodable) == false)
    }

    @Test func standardDiagnosticsRedactTheKeyAndCompatibilitySource() throws {
        let apiKeySentinel = "sk-diagnostic-sentinel"
        let sourceSentinel = "runtimeStorage"
        let credential = try OpenAICredential(apiKey: apiKeySentinel)
        var credentialDump = ""
        var sourceDump = ""

        dump(credential, to: &credentialDump)
        dump(credential.source, to: &sourceDump)

        let diagnosticRepresentations = [
            String(describing: credential),
            String(reflecting: credential),
            credentialDump,
            String(describing: credential.source),
            String(reflecting: credential.source),
            sourceDump,
        ]

        for representation in diagnosticRepresentations {
            #expect(!representation.contains(apiKeySentinel))
            #expect(!representation.contains(sourceSentinel))
        }
        #expect(credential.customMirror.children.isEmpty)
        #expect(credential.source.customMirror.children.isEmpty)
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
