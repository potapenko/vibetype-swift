import Foundation

nonisolated enum KeyboardFixBridgeStoreError: Error, Equatable {
    case appGroupContainerUnavailable
    case readFailed
    case decodeFailed
    case encodeFailed
    case writeFailed
    case claimFailed
    case removeFailed
    case recordTooLarge(maximumBytes: Int, actualBytes: Int)
    case nonIncreasingMetadataRevision(current: UInt64, proposed: UInt64)
    case metadataRevisionExhausted
}

/// Bounded JSON I/O used by the three single-record Keyboard Fix projections.
nonisolated struct KeyboardFixAtomicRecordStore {
    let directoryURL: URL
    let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    func load<Record: Decodable>(
        _ type: Record.Type,
        filename: String,
        maximumBytes: Int
    ) throws -> Record? {
        let url = fileURL(filename)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try readData(at: url, maximumBytes: maximumBytes)
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw KeyboardFixBridgeStoreError.decodeFailed
        }
    }

    func save<Record: Encodable>(
        _ record: Record,
        filename: String,
        maximumBytes: Int
    ) throws {
        let data: Data
        do {
            data = try encoder.encode(record)
        } catch {
            throw KeyboardFixBridgeStoreError.encodeFailed
        }
        guard data.count <= maximumBytes else {
            throw KeyboardFixBridgeStoreError.recordTooLarge(
                maximumBytes: maximumBytes,
                actualBytes: data.count
            )
        }
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try data.write(
                to: fileURL(filename),
                options: [
                    .atomic,
                    .completeFileProtectionUntilFirstUserAuthentication,
                ]
            )
        } catch {
            throw KeyboardFixBridgeStoreError.writeFailed
        }
    }

    /// Atomically removes a record from its published location before decoding
    /// it, so a process crash cannot cause the same value to be delivered twice.
    func take<Record: Decodable>(
        _ type: Record.Type,
        filename: String,
        claimFilename: String,
        maximumBytes: Int
    ) throws -> Record? {
        try remove(filename: claimFilename)
        let sourceURL = fileURL(filename)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return nil
        }
        let claimURL = fileURL(claimFilename)
        do {
            try fileManager.moveItem(at: sourceURL, to: claimURL)
        } catch {
            if !fileManager.fileExists(atPath: sourceURL.path) {
                return nil
            }
            throw KeyboardFixBridgeStoreError.claimFailed
        }

        do {
            guard let record: Record = try load(
                type,
                filename: claimFilename,
                maximumBytes: maximumBytes
            ) else {
                throw KeyboardFixBridgeStoreError.readFailed
            }
            try remove(filename: claimFilename)
            return record
        } catch {
            do {
                try remove(filename: claimFilename)
            } catch {
                throw KeyboardFixBridgeStoreError.removeFailed
            }
            throw error
        }
    }

    func remove(filename: String) throws {
        let url = fileURL(filename)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw KeyboardFixBridgeStoreError.removeFailed
        }
    }

    private func readData(at url: URL, maximumBytes: Int) throws -> Data {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            throw KeyboardFixBridgeStoreError.readFailed
        }
        guard let size = attributes[.size] as? NSNumber else {
            throw KeyboardFixBridgeStoreError.readFailed
        }
        guard size.intValue <= maximumBytes else {
            throw KeyboardFixBridgeStoreError.recordTooLarge(
                maximumBytes: maximumBytes,
                actualBytes: size.intValue
            )
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw KeyboardFixBridgeStoreError.readFailed
        }
        guard data.count <= maximumBytes else {
            throw KeyboardFixBridgeStoreError.recordTooLarge(
                maximumBytes: maximumBytes,
                actualBytes: data.count
            )
        }
        return data
    }

    private func fileURL(_ filename: String) -> URL {
        directoryURL.appendingPathComponent(filename, isDirectory: false)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
