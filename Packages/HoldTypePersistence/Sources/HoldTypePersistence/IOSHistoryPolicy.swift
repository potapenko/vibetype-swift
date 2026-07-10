import Foundation

public enum IOSHistoryPolicyError: Error, Equatable, Sendable {
    case invalidRecord
    case sourceTooLarge
    case malformedData
    case unsupportedSchemaVersion
    case readFailed
    case writeFailed
    case dataProtectionUnavailable
    case slotOccupied
    case compareAndSwapFailed
    case revisionOverflow
    case commitUncertain
    case maintenanceFailed
}

extension IOSHistoryPolicyError: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { "IOSHistoryPolicyError(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

public struct IOSHistoryPolicyState: Equatable, Sendable {
    public let revision: Int64
    public let historyEnabled: Bool
    public let policyGeneration: Int64

    init(
        revision: Int64,
        historyEnabled: Bool,
        policyGeneration: Int64
    ) throws {
        guard revision >= 1,
              revision == policyGeneration else {
            throw IOSHistoryPolicyError.invalidRecord
        }
        self.revision = revision
        self.historyEnabled = historyEnabled
        self.policyGeneration = policyGeneration
    }

    private init(baseline: Void) {
        revision = 1
        historyEnabled = true
        policyGeneration = 1
    }

    static let baseline = Self(baseline: ())
}

extension IOSHistoryPolicyState: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { "IOSHistoryPolicyState(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

public struct IOSHistoryPolicyExpectation: Equatable, Sendable {
    public let revision: Int64
    public let historyEnabled: Bool
    public let policyGeneration: Int64

    public init(state: IOSHistoryPolicyState) {
        revision = state.revision
        historyEnabled = state.historyEnabled
        policyGeneration = state.policyGeneration
    }

    func matches(_ state: IOSHistoryPolicyState) -> Bool {
        self == IOSHistoryPolicyExpectation(state: state)
    }
}

extension IOSHistoryPolicyExpectation: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { "IOSHistoryPolicyExpectation(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

public struct IOSHistoryPolicyMaintenanceReport: Equatable, Sendable {
    public let inspectedEntryCount: Int
    public let inspectedByteCount: Int64
    public let removedFileCount: Int
    public let removedByteCount: Int64
    public let reachedLimit: Bool

    init(_ report: IOSStrictProtectedRecordMaintenanceReport) {
        inspectedEntryCount = report.inspectedEntryCount
        inspectedByteCount = report.inspectedByteCount
        removedFileCount = report.removedFileCount
        removedByteCount = report.removedByteCount
        reachedLimit = report.reachedLimit
    }
}
