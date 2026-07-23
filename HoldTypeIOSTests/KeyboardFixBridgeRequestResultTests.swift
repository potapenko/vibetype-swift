import Foundation
import Testing

struct KeyboardFixBridgeRequestResultTests {
    @Test func requestPreservesOnlyTheExactSelectedSourceAndIdentity() throws {
        let source = "  First line\nSecond line  \n"
        let request = try makeKeyboardFixRequest(sourceText: source)

        #expect(request.sourceText == source)
        #expect(request.sourceKind == .selection)
        #expect(request.identity.requestID == request.requestID)
        #expect(request.identity.documentIdentifier == request.documentIdentifier)
        #expect(request.identity.sourceFingerprint == request.sourceFingerprint)
        #expect(request.isValid(at: request.issuedAt))
        #expect(request.isValid(at: request.expiresAt) == false)
    }

    @Test func requestRequiresSelectionDocumentFingerprintAndSixtySecondTTL() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let common = (
            revision: UInt64(1),
            requestID: UUID(),
            actionIdentifier: "user.action",
            issuedAt: now
        )

        #expect(
            KeyboardFixRequestRecord(
                revision: common.revision,
                requestID: common.requestID,
                actionIdentifier: common.actionIdentifier,
                sourceText: " ",
                documentIdentifier: "document",
                sourceFingerprint: "fingerprint",
                issuedAt: now,
                expiresAt: now.addingTimeInterval(60)
            ) == nil
        )
        #expect(
            KeyboardFixRequestRecord(
                revision: common.revision,
                requestID: common.requestID,
                actionIdentifier: common.actionIdentifier,
                sourceText: "Selected",
                documentIdentifier: "",
                sourceFingerprint: "fingerprint",
                issuedAt: now,
                expiresAt: now.addingTimeInterval(60)
            ) == nil
        )
        #expect(
            KeyboardFixRequestRecord(
                revision: common.revision,
                requestID: common.requestID,
                actionIdentifier: common.actionIdentifier,
                sourceText: "Selected",
                documentIdentifier: "document",
                sourceFingerprint: "",
                issuedAt: now,
                expiresAt: now.addingTimeInterval(60)
            ) == nil
        )
        #expect(
            KeyboardFixRequestRecord(
                revision: common.revision,
                requestID: common.requestID,
                actionIdentifier: common.actionIdentifier,
                sourceText: "Selected",
                documentIdentifier: "document",
                sourceFingerprint: "fingerprint",
                issuedAt: now,
                expiresAt: now.addingTimeInterval(60.001)
            ) == nil
        )
    }

    @Test func requestSourceAndOpaqueMembersUseUTF8Bounds() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let acceptedSource = String(repeating: "é", count: 16 * 1_024)
        let acceptedOpaque = String(repeating: "é", count: 64)
        let request = KeyboardFixRequestRecord(
            revision: 1,
            requestID: UUID(),
            actionIdentifier: acceptedOpaque,
            sourceText: acceptedSource,
            documentIdentifier: acceptedOpaque,
            sourceFingerprint: acceptedOpaque,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )

        #expect(request?.sourceText.utf8.count == 32 * 1_024)
        #expect(request?.documentIdentifier.utf8.count == 128)
        #expect(
            KeyboardFixRequestRecord(
                revision: 1,
                requestID: UUID(),
                actionIdentifier: acceptedOpaque,
                sourceText: acceptedSource + "x",
                documentIdentifier: acceptedOpaque,
                sourceFingerprint: acceptedOpaque,
                issuedAt: now,
                expiresAt: now.addingTimeInterval(60)
            ) == nil
        )
    }

    @Test func resultPayloadCasesAreClosedBoundedAndExact() throws {
        let request = try makeKeyboardFixRequest()
        let processing = KeyboardFixResultRecord(
            identity: request.identity,
            phase: .processing,
            requestIssuedAt: request.issuedAt,
            publishedAt: request.issuedAt.addingTimeInterval(1),
            expiresAt: request.expiresAt
        )
        let exactOutput = "  Result\nwith whitespace  \n"
        let success = KeyboardFixResultRecord(
            identity: request.identity,
            phase: .succeeded,
            outputText: exactOutput,
            requestIssuedAt: request.issuedAt,
            publishedAt: request.issuedAt.addingTimeInterval(2),
            expiresAt: request.expiresAt
        )
        let failure = KeyboardFixResultRecord(
            identity: request.identity,
            phase: .failed,
            failureCode: .timedOut,
            requestIssuedAt: request.issuedAt,
            publishedAt: request.issuedAt.addingTimeInterval(2),
            expiresAt: request.expiresAt
        )

        #expect(processing?.isTerminal == false)
        #expect(success?.outputText == exactOutput)
        #expect(success?.isTerminal == true)
        #expect(failure?.failureCode == .timedOut)
        #expect(
            KeyboardFixResultRecord(
                identity: request.identity,
                phase: .succeeded,
                outputText: " ",
                requestIssuedAt: request.issuedAt,
                publishedAt: request.issuedAt.addingTimeInterval(2),
                expiresAt: request.expiresAt
            ) == nil
        )
        #expect(
            KeyboardFixResultRecord(
                identity: request.identity,
                phase: .processing,
                outputText: "Unexpected",
                requestIssuedAt: request.issuedAt,
                publishedAt: request.issuedAt.addingTimeInterval(2),
                expiresAt: request.expiresAt
            ) == nil
        )
        #expect(
            KeyboardFixFailureCode.allCases.allSatisfy {
                $0.rawValue.utf8.count <= 256
            }
        )
    }

    @Test func resultOutputAndOverallLifetimeAreBounded() throws {
        let request = try makeKeyboardFixRequest()
        let acceptedOutput = String(repeating: "é", count: 32 * 1_024)

        #expect(
            KeyboardFixResultRecord(
                identity: request.identity,
                phase: .succeeded,
                outputText: acceptedOutput,
                requestIssuedAt: request.issuedAt,
                publishedAt: request.issuedAt.addingTimeInterval(1),
                expiresAt: request.expiresAt
            ) != nil
        )
        #expect(
            KeyboardFixResultRecord(
                identity: request.identity,
                phase: .succeeded,
                outputText: acceptedOutput + "x",
                requestIssuedAt: request.issuedAt,
                publishedAt: request.issuedAt.addingTimeInterval(1),
                expiresAt: request.expiresAt
            ) == nil
        )
        #expect(
            KeyboardFixResultRecord(
                identity: request.identity,
                phase: .failed,
                failureCode: .providerFailed,
                requestIssuedAt: request.issuedAt,
                publishedAt: request.issuedAt.addingTimeInterval(1),
                expiresAt: request.expiresAt.addingTimeInterval(0.001)
            ) == nil
        )
    }

    @Test func requestAndResultDescriptionsRedactAllTextAndHostContext() throws {
        let request = try makeKeyboardFixRequest(
            sourceText: "PRIVATE-SOURCE",
            documentIdentifier: "PRIVATE-DOCUMENT",
            sourceFingerprint: "PRIVATE-FINGERPRINT"
        )
        let result = try makeKeyboardFixResult(
            request: request,
            outputText: "PRIVATE-OUTPUT"
        )
        var requestDump = ""
        var resultDump = ""
        dump(request, to: &requestDump)
        dump(result, to: &resultDump)

        for rendered in [
            String(reflecting: request),
            requestDump,
            String(reflecting: result),
            resultDump,
        ] {
            for secret in [
                "PRIVATE-SOURCE",
                "PRIVATE-DOCUMENT",
                "PRIVATE-FINGERPRINT",
                "PRIVATE-OUTPUT",
            ] {
                #expect(rendered.contains(secret) == false)
            }
            #expect(rendered.contains("<redacted>"))
        }
    }
}
