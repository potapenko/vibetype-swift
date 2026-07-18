import Foundation
import HoldTypeDomain

/// A neutral, process-local audio reader that can be consumed by one OpenAI
/// transcription request. It carries no filesystem location or durable identity.
public struct OpenAITranscriptionAudioReader: Sendable {
    public static let maximumReadByteCount = 64 * 1_024

    public typealias ReadOperation = @Sendable (
        _ offset: Int64,
        _ maximumByteCount: Int
    ) async throws -> Data

    private let state: OpenAITranscriptionAudioReaderState

    public init(read: @escaping ReadOperation) {
        state = OpenAITranscriptionAudioReaderState(read: read)
    }

    func claim() throws -> OpenAITranscriptionAudioReaderLease {
        try state.claim()
    }

    func invalidate() {
        state.invalidate()
    }
}

extension OpenAITranscriptionAudioReader: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { "OpenAITranscriptionAudioReader(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [(label: String?, value: Any)](),
            displayStyle: .struct
        )
    }
}

/// Runtime-only input for descriptor-backed or otherwise bounded audio.
/// The service consumes its reader exactly once and never materializes a source path.
public struct OpenAIReaderTranscriptionRequest: Sendable {
    public enum AudioFormat: CaseIterable, Equatable, Sendable {
        case m4a
        case wav
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidDurationMilliseconds
        case invalidByteCount
        case invalidModel
        case invalidLanguageCode
    }

    /// Accepts recorder close post-roll through the longest supported recording.
    /// Per-attempt validation applies the selected limit earlier; this is only
    /// the absolute local media ceiling, not a provider duration limit.
    public static let maximumAudioByteCountExclusive: Int64 = 25_000_000

    public let format: AudioFormat
    public let durationMilliseconds: Int64
    public let byteCount: Int64
    public let model: String
    public let languageCode: String?
    public let promptComposition: TranscriptionPromptComposition

    private let reader: OpenAITranscriptionAudioReader

    public init(
        format: AudioFormat,
        durationMilliseconds: Int64,
        byteCount: Int64,
        model: String,
        languageCode: String?,
        promptComposition: TranscriptionPromptComposition,
        reader: OpenAITranscriptionAudioReader
    ) throws {
        guard durationMilliseconds > 0,
              durationMilliseconds <= RecordingDurationLimit
                .maximumSupportedFinalizedMediaDurationMilliseconds else {
            throw ValidationError.invalidDurationMilliseconds
        }
        guard byteCount > 0,
              byteCount < Self.maximumAudioByteCountExclusive else {
            throw ValidationError.invalidByteCount
        }
        guard !model.isEmpty,
              model == model.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ValidationError.invalidModel
        }
        guard Self.isValidLanguageCode(languageCode) else {
            throw ValidationError.invalidLanguageCode
        }

        self.format = format
        self.durationMilliseconds = durationMilliseconds
        self.byteCount = byteCount
        self.model = model
        self.languageCode = languageCode
        self.promptComposition = promptComposition
        self.reader = reader
    }

    func claimReader() throws -> OpenAITranscriptionAudioReaderLease {
        try reader.claim()
    }

    func invalidateReader() {
        reader.invalidate()
    }

    private static func isValidLanguageCode(_ value: String?) -> Bool {
        guard let value else { return true }
        guard value.count == 2 || value.count == 3 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (97...122).contains(scalar.value)
        }
    }
}

extension OpenAIReaderTranscriptionRequest: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { "OpenAIReaderTranscriptionRequest(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [(label: String?, value: Any)](),
            displayStyle: .struct
        )
    }
}

nonisolated enum OpenAITranscriptionAudioReaderError: Error, Equatable, Sendable {
    case alreadyConsumed
    case invalidRead
}

nonisolated final class OpenAITranscriptionAudioReaderState: @unchecked Sendable {
    private enum State {
        case available(OpenAITranscriptionAudioReader.ReadOperation)
        case claimed(UUID, OpenAITranscriptionAudioReader.ReadOperation)
        case retired
    }

    private let lock = NSLock()
    private var state: State

    init(read: @escaping OpenAITranscriptionAudioReader.ReadOperation) {
        state = .available(read)
    }

    func claim() throws -> OpenAITranscriptionAudioReaderLease {
        try lock.withLock {
            guard case .available(let read) = state else {
                throw OpenAITranscriptionAudioReaderError.alreadyConsumed
            }
            let identifier = UUID()
            state = .claimed(identifier, read)
            return OpenAITranscriptionAudioReaderLease(
                identifier: identifier,
                state: self
            )
        }
    }

    func read(
        identifier: UUID,
        atOffset offset: Int64,
        maximumByteCount: Int
    ) async throws -> Data {
        guard offset >= 0,
              maximumByteCount > 0,
              maximumByteCount <= OpenAITranscriptionAudioReader.maximumReadByteCount else {
            throw OpenAITranscriptionAudioReaderError.invalidRead
        }
        try Task.checkCancellation()
        let operation = try lock.withLock {
            guard case .claimed(let currentIdentifier, let read) = state,
                  currentIdentifier == identifier else {
                throw CancellationError()
            }
            return read
        }
        let data = try await operation(offset, maximumByteCount)
        try Task.checkCancellation()
        guard data.count <= maximumByteCount else {
            throw OpenAITranscriptionAudioReaderError.invalidRead
        }
        let isCurrent = lock.withLock {
            guard case .claimed(let currentIdentifier, _) = state else {
                return false
            }
            return currentIdentifier == identifier
        }
        guard isCurrent else { throw CancellationError() }
        return data
    }

    func retire(identifier: UUID) {
        lock.withLock {
            guard case .claimed(let currentIdentifier, _) = state,
                  currentIdentifier == identifier else {
                return
            }
            state = .retired
        }
    }

    func invalidate() {
        lock.withLock {
            state = .retired
        }
    }
}

nonisolated final class OpenAITranscriptionAudioReaderLease: @unchecked Sendable {
    private let identifier: UUID
    private let state: OpenAITranscriptionAudioReaderState

    init(identifier: UUID, state: OpenAITranscriptionAudioReaderState) {
        self.identifier = identifier
        self.state = state
    }

    func read(atOffset offset: Int64, maximumByteCount: Int) async throws -> Data {
        try await state.read(
            identifier: identifier,
            atOffset: offset,
            maximumByteCount: maximumByteCount
        )
    }

    func retire() {
        state.retire(identifier: identifier)
    }

    deinit {
        retire()
    }
}
