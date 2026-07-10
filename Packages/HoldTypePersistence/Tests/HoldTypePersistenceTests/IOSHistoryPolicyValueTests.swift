import Foundation
import Testing
@testable import HoldTypePersistence

struct IOSHistoryPolicyValueTests {
    @Test func baselineAndExpectationsUseExactOneOneState() throws {
        let baseline = IOSHistoryPolicyState.baseline
        #expect(baseline.revision == 1)
        #expect(baseline.policyGeneration == 1)
        #expect(baseline.historyEnabled)
        #expect(IOSHistoryPolicyExpectation(state: baseline).matches(baseline))

        #expect(throws: IOSHistoryPolicyError.invalidRecord) {
            _ = try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: true,
                policyGeneration: 1
            )
        }
        #expect(throws: IOSHistoryPolicyError.invalidRecord) {
            _ = try IOSHistoryPolicyState(
                revision: 0,
                historyEnabled: true,
                policyGeneration: 0
            )
        }
    }

    @Test func publicDiagnosticsAndReflectionAreRedacted() throws {
        let state = IOSHistoryPolicyState.baseline
        let expectation = IOSHistoryPolicyExpectation(state: state)
        let error = IOSHistoryPolicyError.compareAndSwapFailed

        #expect(String(describing: state) == "IOSHistoryPolicyState(redacted)")
        #expect(String(reflecting: expectation) == "IOSHistoryPolicyExpectation(redacted)")
        #expect(String(describing: error) == "IOSHistoryPolicyError(redacted)")
        #expect(state.customMirror.children.isEmpty)
        #expect(expectation.customMirror.children.isEmpty)
        #expect(error.customMirror.children.isEmpty)
    }

    @Test func storageLocationAndStrictConfigurationAreExact() {
        let base = URL(fileURLWithPath: "/private/app-support", isDirectory: true)
        #expect(
            IOSHistoryPolicyStorageLocation.fileURL(in: base).path
                == "/private/app-support/HoldType/ios-history-policy.json"
        )
        let configuration = IOSStrictProtectedRecordConfiguration.historyPolicy
        #expect(configuration.rootDirectoryName == "HoldType")
        #expect(configuration.fileName == "ios-history-policy.json")
        #expect(configuration.maximumByteCount == 16_384)
        #expect(configuration.marker?.name == "com.holdtype.ios.history-policy")
        #expect(configuration.marker?.value == Array("v1".utf8))
    }

    @Test func publicAndAuthorityValuesAreSendable() {
        requirePolicySendable(IOSHistoryPolicyState.self)
        requirePolicySendable(IOSHistoryPolicyExpectation.self)
        requirePolicySendable(IOSHistoryPolicyError.self)
        requirePolicySendable(IOSHistoryPolicyReceipt.self)
    }
}

private func requirePolicySendable<Value: Sendable>(_ type: Value.Type) {}
