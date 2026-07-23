import Foundation

/// Three bounded atomic projections with no queue or history:
/// app metadata, extension request, and app state/result.
nonisolated struct KeyboardFixBridgeStore {
    private let records: KeyboardFixAtomicRecordStore

    init(directoryURL: URL, fileManager: FileManager = .default) {
        records = KeyboardFixAtomicRecordStore(
            directoryURL: directoryURL,
            fileManager: fileManager
        )
    }

    static func appGroup(
        fileManager: FileManager = .default
    ) throws -> KeyboardFixBridgeStore {
        guard let directoryURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier:
                KeyboardBridgeConfiguration.appGroupIdentifier
        ) else {
            throw KeyboardFixBridgeStoreError.appGroupContainerUnavailable
        }
        return KeyboardFixBridgeStore(
            directoryURL: directoryURL,
            fileManager: fileManager
        )
    }

    func loadMetadata() throws -> KeyboardFixMetadataSnapshot? {
        try records.load(
            KeyboardFixMetadataSnapshot.self,
            filename: KeyboardFixBridgeConfiguration.metadataFilename,
            maximumBytes: KeyboardFixBridgeConfiguration.maximumMetadataBytes
        )
    }

    func nextMetadataRevision() throws -> UInt64 {
        guard let current = try loadMetadata() else {
            return 1
        }
        guard current.revision < UInt64.max else {
            throw KeyboardFixBridgeStoreError.metadataRevisionExhausted
        }
        return current.revision + 1
    }

    func publishMetadata(_ snapshot: KeyboardFixMetadataSnapshot) throws {
        if let current = try loadMetadata(),
           snapshot.revision <= current.revision {
            throw KeyboardFixBridgeStoreError.nonIncreasingMetadataRevision(
                current: current.revision,
                proposed: snapshot.revision
            )
        }
        try records.save(
            snapshot,
            filename: KeyboardFixBridgeConfiguration.metadataFilename,
            maximumBytes: KeyboardFixBridgeConfiguration.maximumMetadataBytes
        )
    }

    /// Extension writer. A newer request retires all earlier transient results.
    func publishRequest(_ request: KeyboardFixRequestRecord) throws {
        try records.remove(
            filename: KeyboardFixBridgeConfiguration.resultFilename
        )
        try records.remove(
            filename: KeyboardFixBridgeConfiguration.resultClaimFilename
        )
        try records.remove(
            filename: KeyboardFixBridgeConfiguration.requestClaimFilename
        )
        try records.save(
            request,
            filename: KeyboardFixBridgeConfiguration.requestFilename,
            maximumBytes: KeyboardFixBridgeConfiguration.maximumRequestBytes
        )
    }

    /// App reader. The request is removed atomically before it is returned.
    func consumeRequest(
        at date: Date = Date()
    ) throws -> KeyboardFixRequestRecord? {
        guard let request: KeyboardFixRequestRecord = try records.take(
            KeyboardFixRequestRecord.self,
            filename: KeyboardFixBridgeConfiguration.requestFilename,
            claimFilename: KeyboardFixBridgeConfiguration.requestClaimFilename,
            maximumBytes: KeyboardFixBridgeConfiguration.maximumRequestBytes
        ) else {
            return nil
        }
        return request.isValid(at: date) ? request : nil
    }

    /// App writer. Processing may later be atomically replaced by a terminal
    /// success or closed failure for the same request identity.
    func publishResult(_ result: KeyboardFixResultRecord) throws {
        try records.save(
            result,
            filename: KeyboardFixBridgeConfiguration.resultFilename,
            maximumBytes: KeyboardFixBridgeConfiguration.maximumResultBytes
        )
    }

    /// Read-only progress lookup. It never authorizes replacement.
    func loadResult(
        matching identity: KeyboardFixRequestIdentity,
        at date: Date = Date()
    ) throws -> KeyboardFixResultRecord? {
        guard let result: KeyboardFixResultRecord = try records.load(
            KeyboardFixResultRecord.self,
            filename: KeyboardFixBridgeConfiguration.resultFilename,
            maximumBytes: KeyboardFixBridgeConfiguration.maximumResultBytes
        ),
        result.matches(identity),
        result.isValid(at: date)
        else {
            return nil
        }
        return result
    }

    /// Extension reader. A terminal value is acknowledged by removal before
    /// return, ensuring at most one replacement invocation across restarts.
    func consumeTerminalResult(
        matching identity: KeyboardFixRequestIdentity,
        at date: Date = Date()
    ) throws -> KeyboardFixResultRecord? {
        guard let result: KeyboardFixResultRecord = try records.take(
            KeyboardFixResultRecord.self,
            filename: KeyboardFixBridgeConfiguration.resultFilename,
            claimFilename: KeyboardFixBridgeConfiguration.resultClaimFilename,
            maximumBytes: KeyboardFixBridgeConfiguration.maximumResultBytes
        ),
        result.matches(identity),
        result.isValid(at: date),
        result.isTerminal
        else {
            return nil
        }
        return result
    }

    func cancelRequest(requestID: UUID) throws {
        if let request: KeyboardFixRequestRecord = try records.load(
            KeyboardFixRequestRecord.self,
            filename: KeyboardFixBridgeConfiguration.requestFilename,
            maximumBytes: KeyboardFixBridgeConfiguration.maximumRequestBytes
        ),
        request.requestID == requestID {
            try records.remove(
                filename: KeyboardFixBridgeConfiguration.requestFilename
            )
        }
        if let result: KeyboardFixResultRecord = try records.load(
            KeyboardFixResultRecord.self,
            filename: KeyboardFixBridgeConfiguration.resultFilename,
            maximumBytes: KeyboardFixBridgeConfiguration.maximumResultBytes
        ),
        result.requestID == requestID {
            try records.remove(
                filename: KeyboardFixBridgeConfiguration.resultFilename
            )
        }
    }

    func removeAllTransientRecords() throws {
        for filename in [
            KeyboardFixBridgeConfiguration.requestFilename,
            KeyboardFixBridgeConfiguration.requestClaimFilename,
            KeyboardFixBridgeConfiguration.resultFilename,
            KeyboardFixBridgeConfiguration.resultClaimFilename,
        ] {
            try records.remove(filename: filename)
        }
    }
}
