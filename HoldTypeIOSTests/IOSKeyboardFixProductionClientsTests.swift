import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
import Testing
@testable import HoldTypeIOS

struct IOSKeyboardFixProductionClientsTests {
    @Test func successfulOutputIsReturnedExactly() throws {
        let action = try customAction()
        let output = "  Exact provider whitespace\n"

        #expect(
            try IOSKeyboardFixProductionClients.output(
                from: .success(output),
                action: action
            ) == output
        )
    }

    @Test func voiceFailuresReduceToClosedKeyboardFailures() throws {
        let translate = TextFixCatalog.defaults.actions[0]
        let custom = try customAction()
        let cases: [
            (
                IOSVoiceDraftTextActionFailure,
                TextFixAction,
                IOSKeyboardFixExecutionFailure
            )
        ] = [
            (.busy, custom, .actionUnavailable),
            (.invalidText, custom, .invalidOutput),
            (.sourceTooLarge, custom, .invalidOutput),
            (.invalidConfiguration, translate, .translationUnavailable),
            (.invalidConfiguration, custom, .actionUnavailable),
            (.credentialUnavailable, custom, .credentialUnavailable),
            (.consentUnavailable, custom, .consentRequired),
            (.networkUnavailable, custom, .providerFailed),
            (.timedOut, custom, .timedOut),
            (.providerUnavailable, custom, .providerFailed),
            (.invalidResponse, custom, .invalidOutput),
            (.draftChanged, custom, .persistenceFailed),
            (.saveFailed, custom, .persistenceFailed),
            (.cancelled, custom, .cancelled),
        ]

        for (failure, action, expected) in cases {
            #expect(
                IOSKeyboardFixProductionClients.executionFailure(
                    from: failure,
                    action: action
                ) == expected
            )
        }
    }

    private func customAction() throws -> TextFixAction {
        try TextFixAction(
            id: "user.exact",
            kind: .customPrompt,
            title: "Exact",
            icon: .custom,
            prompt: "Return exact output."
        )
    }
}
