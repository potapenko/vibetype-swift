import Darwin
import Foundation
import HoldTypeDomain

enum IOSForegroundVoiceCaptureSourcePhase: String, CaseIterable, Sendable {
    case active = "active-v1"
    case finalizing = "finalizing-v1"
    case completed = "completed-v1"
    case preparingPending = "preparing-pending-v1"
    case transferred = "transferred-v1"
    case discarding = "discarding-v1"
}

struct IOSForegroundVoiceCaptureCreationIntent: Equatable, Sendable {
    let attemptID: UUID
    let outputIntent: DictationOutputIntent
    let format: IOSPendingRecordingAudioFormat
    let creationMilliseconds: UInt64
}

struct IOSForegroundVoiceCaptureIdentity: Equatable, Sendable {
    let attemptID: UUID
    let outputIntent: DictationOutputIntent
    let format: IOSPendingRecordingAudioFormat
    let creationMilliseconds: UInt64
    let device: UInt64
    let inode: UInt64
    let generation: UInt32
}

struct IOSForegroundVoiceCaptureCompletion: Equatable, Sendable {
    let durationMilliseconds: UInt32
    let byteCount: UInt64
    let modificationSeconds: Int64
    let modificationNanoseconds: UInt32
}

enum IOSForegroundVoiceCaptureSourceWireCodec {
    static let latestCreationMilliseconds: UInt64 = 253_402_300_799_999

    static func creationIntent(
        _ value: IOSForegroundVoiceCaptureCreationIntent
    ) -> [UInt8] {
        var bytes: [UInt8] = [1]
        bytes.append(contentsOf: uuidBytes(value.attemptID))
        bytes.append(outputIntentByte(value.outputIntent))
        bytes.append(formatByte(value.format))
        bytes.appendBigEndian(value.creationMilliseconds)
        precondition(bytes.count == 27)
        return bytes
    }

    static func decodeCreationIntent(
        _ bytes: [UInt8]
    ) -> IOSForegroundVoiceCaptureCreationIntent? {
        guard bytes.count == 27, bytes[0] == 1 else { return nil }
        var reader = CaptureWireReader(bytes: bytes, offset: 1)
        guard let attemptID = reader.readUUID(),
              let outputIntent = reader.readOutputIntent(),
              let format = reader.readFormat(),
              let creationMilliseconds: UInt64 = reader.readBigEndian(),
              creationMilliseconds <= latestCreationMilliseconds,
              reader.isAtEnd else {
            return nil
        }
        return IOSForegroundVoiceCaptureCreationIntent(
            attemptID: attemptID,
            outputIntent: outputIntent,
            format: format,
            creationMilliseconds: creationMilliseconds
        )
    }

    static func identity(
        _ value: IOSForegroundVoiceCaptureIdentity
    ) -> [UInt8] {
        var bytes: [UInt8] = [1]
        bytes.append(contentsOf: uuidBytes(value.attemptID))
        bytes.append(outputIntentByte(value.outputIntent))
        bytes.append(formatByte(value.format))
        bytes.appendBigEndian(value.creationMilliseconds)
        bytes.appendBigEndian(value.device)
        bytes.appendBigEndian(value.inode)
        bytes.appendBigEndian(value.generation)
        precondition(bytes.count == 47)
        return bytes
    }

    static func decodeIdentity(
        _ bytes: [UInt8]
    ) -> IOSForegroundVoiceCaptureIdentity? {
        guard bytes.count == 47, bytes[0] == 1 else { return nil }
        var reader = CaptureWireReader(bytes: bytes, offset: 1)
        guard let attemptID = reader.readUUID(),
              let outputIntent = reader.readOutputIntent(),
              let format = reader.readFormat(),
              let creationMilliseconds: UInt64 = reader.readBigEndian(),
              creationMilliseconds <= latestCreationMilliseconds,
              let device: UInt64 = reader.readBigEndian(),
              let inode: UInt64 = reader.readBigEndian(),
              let generation: UInt32 = reader.readBigEndian(),
              reader.isAtEnd else {
            return nil
        }
        return IOSForegroundVoiceCaptureIdentity(
            attemptID: attemptID,
            outputIntent: outputIntent,
            format: format,
            creationMilliseconds: creationMilliseconds,
            device: device,
            inode: inode,
            generation: generation
        )
    }

    static func completion(
        _ value: IOSForegroundVoiceCaptureCompletion
    ) -> [UInt8] {
        var bytes: [UInt8] = [1]
        bytes.appendBigEndian(value.durationMilliseconds)
        bytes.appendBigEndian(value.byteCount)
        bytes.appendBigEndian(UInt64(bitPattern: value.modificationSeconds))
        bytes.appendBigEndian(value.modificationNanoseconds)
        precondition(bytes.count == 25)
        return bytes
    }

    static func decodeCompletion(
        _ bytes: [UInt8]
    ) -> IOSForegroundVoiceCaptureCompletion? {
        guard bytes.count == 25, bytes[0] == 1 else { return nil }
        var reader = CaptureWireReader(bytes: bytes, offset: 1)
        guard let durationMilliseconds: UInt32 = reader.readBigEndian(),
              let byteCount: UInt64 = reader.readBigEndian(),
              let modificationBits: UInt64 = reader.readBigEndian(),
              let modificationNanoseconds: UInt32 = reader.readBigEndian(),
              modificationNanoseconds < 1_000_000_000,
              reader.isAtEnd else {
            return nil
        }
        return IOSForegroundVoiceCaptureCompletion(
            durationMilliseconds: durationMilliseconds,
            byteCount: byteCount,
            modificationSeconds: Int64(bitPattern: modificationBits),
            modificationNanoseconds: modificationNanoseconds
        )
    }

    static func phase(_ phase: IOSForegroundVoiceCaptureSourcePhase) -> [UInt8] {
        Array(phase.rawValue.utf8)
    }

    static func decodePhase(
        _ bytes: [UInt8]
    ) -> IOSForegroundVoiceCaptureSourcePhase? {
        guard let value = String(bytes: bytes, encoding: .ascii) else { return nil }
        return IOSForegroundVoiceCaptureSourcePhase(rawValue: value)
    }

    static func finalName(
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat
    ) -> String {
        "capture-v1-\(canonicalUUID(attemptID)).\(format.fileExtension)"
    }

    static func hiddenName(
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat
    ) -> String {
        ".capture-source-creating-v1-\(canonicalUUID(attemptID)).\(format.fileExtension)"
    }

    static func parseFinalName(
        _ name: String
    ) -> (attemptID: UUID, format: IOSPendingRecordingAudioFormat)? {
        parseName(name, prefix: "capture-v1-")
    }

    static func parseHiddenName(
        _ name: String
    ) -> (attemptID: UUID, format: IOSPendingRecordingAudioFormat)? {
        parseName(name, prefix: ".capture-source-creating-v1-")
    }

    private static func parseName(
        _ name: String,
        prefix: String
    ) -> (attemptID: UUID, format: IOSPendingRecordingAudioFormat)? {
        guard name.hasPrefix(prefix) else { return nil }
        let remainder = String(name.dropFirst(prefix.count))
        guard let dot = remainder.lastIndex(of: ".") else { return nil }
        let uuidText = String(remainder[..<dot])
        let extensionText = String(remainder[remainder.index(after: dot)...])
        guard uuidText.count == 36,
              uuidText == uuidText.lowercased(),
              let attemptID = UUID(uuidString: uuidText),
              canonicalUUID(attemptID) == uuidText else {
            return nil
        }
        let format: IOSPendingRecordingAudioFormat
        switch extensionText {
        case "m4a": format = .m4a
        case "wav": format = .wav
        default: return nil
        }
        return (attemptID, format)
    }

    private static func canonicalUUID(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }

    private static func uuidBytes(_ value: UUID) -> [UInt8] {
        var uuid = value.uuid
        return withUnsafeBytes(of: &uuid) { Array($0) }
    }

    private static func outputIntentByte(_ value: DictationOutputIntent) -> UInt8 {
        switch value {
        case .standard: 1
        case .translate: 2
        }
    }

    private static func formatByte(_ value: IOSPendingRecordingAudioFormat) -> UInt8 {
        switch value {
        case .m4a: 1
        case .wav: 2
        }
    }
}

private struct CaptureWireReader {
    let bytes: [UInt8]
    var offset: Int

    var isAtEnd: Bool { offset == bytes.count }

    mutating func readUUID() -> UUID? {
        guard offset + 16 <= bytes.count else { return nil }
        let value = bytes[offset..<(offset + 16)]
        offset += 16
        let tuple: uuid_t = (
            value[value.startIndex], value[value.startIndex + 1],
            value[value.startIndex + 2], value[value.startIndex + 3],
            value[value.startIndex + 4], value[value.startIndex + 5],
            value[value.startIndex + 6], value[value.startIndex + 7],
            value[value.startIndex + 8], value[value.startIndex + 9],
            value[value.startIndex + 10], value[value.startIndex + 11],
            value[value.startIndex + 12], value[value.startIndex + 13],
            value[value.startIndex + 14], value[value.startIndex + 15]
        )
        return UUID(uuid: tuple)
    }

    mutating func readOutputIntent() -> DictationOutputIntent? {
        guard let byte = readByte() else { return nil }
        switch byte {
        case 1: return .standard
        case 2: return .translate
        default: return nil
        }
    }

    mutating func readFormat() -> IOSPendingRecordingAudioFormat? {
        guard let byte = readByte() else { return nil }
        switch byte {
        case 1: return .m4a
        case 2: return .wav
        default: return nil
        }
    }

    mutating func readBigEndian<T: FixedWidthInteger>() -> T? {
        let count = MemoryLayout<T>.size
        guard offset + count <= bytes.count else { return nil }
        var result: T = 0
        for byte in bytes[offset..<(offset + count)] {
            result = (result << 8) | T(byte)
        }
        offset += count
        return result
    }

    private mutating func readByte() -> UInt8? {
        guard offset < bytes.count else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }
}

private extension Array where Element == UInt8 {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        for shift in stride(from: T.bitWidth - 8, through: 0, by: -8) {
            append(UInt8(truncatingIfNeeded: value >> T(shift)))
        }
    }
}
