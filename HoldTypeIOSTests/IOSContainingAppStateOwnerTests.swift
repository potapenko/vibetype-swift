import Foundation
import HoldTypeDomain
import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSContainingAppStateOwnerTests {
    @Test func productionOwnersLoadMissingFilesAsDefaultsWithoutWriting()
        async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ios-state-owner-production-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let settingsOwner = IOSAppSettingsStateOwner(
            applicationSupportDirectoryURL: root
        )
        let libraryOwner = IOSLibraryStateOwner(
            applicationSupportDirectoryURL: root
        )
        let settingsURL = IOSAppSettingsStorageLocation.fileURL(in: root)
        let libraryURL = IOSLibraryStorageLocation.fileURL(in: root)

        #expect(!FileManager.default.fileExists(atPath: settingsURL.path))
        #expect(!FileManager.default.fileExists(atPath: libraryURL.path))
        #expect(try await settingsOwner.load() == .ready(.defaults))
        #expect(try await libraryOwner.load() == .ready(.defaults))
        #expect(!FileManager.default.fileExists(atPath: settingsURL.path))
        #expect(!FileManager.default.fileExists(atPath: libraryURL.path))
    }

    @Test func passiveConstructionAndConcurrentInitialLoadsCoalesce()
        async throws {
        let settingsRepository = StateOwnerRepositoryFixture(
            initialValue: IOSAppSettings.defaults,
            suspendNextLoad: true
        )
        let libraryRepository = StateOwnerRepositoryFixture(
            initialValue: IOSLibraryContent.defaults,
            suspendNextLoad: true
        )
        let settingsOwner = IOSAppSettingsStateOwner(
            load: { try await settingsRepository.load() },
            commit: { try await settingsRepository.commit($0) }
        )
        let libraryOwner = IOSLibraryStateOwner(
            load: { try await libraryRepository.load() },
            commit: { try await libraryRepository.commit($0) }
        )

        #expect(settingsOwner.state == .notLoaded)
        #expect(libraryOwner.state == .notLoaded)
        #expect(await settingsRepository.loadCallCount() == 0)
        #expect(await libraryRepository.loadCallCount() == 0)
        #expect(await settingsRepository.commitCallCount() == 0)
        #expect(await libraryRepository.commitCallCount() == 0)

        let firstSettingsLoad = Task { try await settingsOwner.load() }
        let secondSettingsLoad = Task { try await settingsOwner.load() }
        try await stateOwnerEventually {
            await settingsRepository.loadCallCount() == 1
        }
        #expect(await settingsRepository.loadCallCount() == 1)
        await settingsRepository.resumeLoad()
        #expect(try await firstSettingsLoad.value == .ready(.defaults))
        #expect(try await secondSettingsLoad.value == .ready(.defaults))
        #expect(await settingsRepository.loadCallCount() == 1)
        #expect(await settingsRepository.commitCallCount() == 0)

        let firstLibraryLoad = Task { try await libraryOwner.load() }
        let secondLibraryLoad = Task { try await libraryOwner.load() }
        try await stateOwnerEventually {
            await libraryRepository.loadCallCount() == 1
        }
        #expect(await libraryRepository.loadCallCount() == 1)
        await libraryRepository.resumeLoad()
        #expect(try await firstLibraryLoad.value == .ready(.defaults))
        #expect(try await secondLibraryLoad.value == .ready(.defaults))
        #expect(await libraryRepository.loadCallCount() == 1)
        #expect(await libraryRepository.commitCallCount() == 0)
    }

    @Test func loadFailuresExposeNoDefaultsAndCanRetry() async throws {
        let settingsRepository = StateOwnerRepositoryFixture(
            initialValue: settings(model: "durable-model"),
            loadFailures: [true, false]
        )
        let libraryRepository = StateOwnerRepositoryFixture(
            initialValue: library(entry: "Durable Library"),
            loadFailures: [true, false]
        )
        let settingsOwner = IOSAppSettingsStateOwner(
            load: { try await settingsRepository.load() },
            commit: { try await settingsRepository.commit($0) }
        )
        let libraryOwner = IOSLibraryStateOwner(
            load: { try await libraryRepository.load() },
            commit: { try await libraryRepository.commit($0) }
        )

        await expectStateOwnerError(.loadFailed) {
            _ = try await settingsOwner.load()
        }
        #expect(settingsOwner.state == .loadFailed)
        #expect(await settingsRepository.commitCallCount() == 0)
        #expect(
            try await settingsOwner.load()
                == .ready(settings(model: "durable-model"))
        )

        await expectStateOwnerError(.loadFailed) {
            _ = try await libraryOwner.load()
        }
        #expect(libraryOwner.state == .loadFailed)
        #expect(await libraryRepository.commitCallCount() == 0)
        #expect(
            try await libraryOwner.load()
                == .ready(library(entry: "Durable Library"))
        )
    }

    @Test func settingsMutationsAreFIFOAndFailedSaveRollsBack()
        async throws {
        let fifoRepository = StateOwnerRepositoryFixture(
            initialValue: IOSAppSettings.defaults,
            suspendNextCommit: true
        )
        let fifoOwner = IOSAppSettingsStateOwner(
            load: { try await fifoRepository.load() },
            commit: { try await fifoRepository.commit($0) }
        )
        _ = try await fifoOwner.load()

        let firstMutation = Task {
            try await fifoOwner.update {
                $0.keepLatestResult = false
            }
        }
        try await stateOwnerEventually {
            await fifoRepository.commitCallCount() == 1
        }
        let providerObservation = StateOwnerProviderObservation<IOSAppSettings>()
        let providerSnapshot = Task {
            let value = try await fifoOwner
                .confirmedValueForProviderAction()
            await providerObservation.record(value)
            return value
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(await providerObservation.value() == nil)
        let secondMutation = Task {
            try await fifoOwner.update {
                $0.localTextCleanupEnabled = false
            }
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(await fifoRepository.commitCallCount() == 1)

        await fifoRepository.resumeCommit()
        _ = try await firstMutation.value
        let providerValue = try await providerSnapshot.value
        #expect(!providerValue.keepLatestResult)
        _ = try await secondMutation.value

        let committed = await fifoRepository.storedValue()
        #expect(!committed.keepLatestResult)
        #expect(!committed.localTextCleanupEnabled)
        let candidates = await fifoRepository.committedCandidates()
        #expect(candidates.count == 2)
        #expect(!candidates[1].keepLatestResult)
        #expect(!candidates[1].localTextCleanupEnabled)

        let rollbackRepository = StateOwnerRepositoryFixture(
            initialValue: IOSAppSettings.defaults,
            commitFailures: [true, false],
            suspendNextCommit: true
        )
        let rollbackOwner = IOSAppSettingsStateOwner(
            load: { try await rollbackRepository.load() },
            commit: { try await rollbackRepository.commit($0) }
        )
        _ = try await rollbackOwner.load()

        let failedMutation = Task {
            try await rollbackOwner.update {
                $0.keepLatestResult = false
            }
        }
        try await stateOwnerEventually {
            await rollbackRepository.commitCallCount() == 1
        }
        let rollbackProviderSnapshot = Task {
            try await rollbackOwner.confirmedValueForProviderAction()
        }
        for _ in 0..<20 { await Task.yield() }
        await rollbackRepository.resumeCommit()
        await expectTaskStateOwnerError(.saveFailed, task: failedMutation)
        #expect(
            rollbackOwner.state
                == .saveFailed(lastDurableValue: .defaults)
        )
        #expect(
            try await rollbackProviderSnapshot.value == .defaults
        )
        #expect(await rollbackRepository.storedValue() == .defaults)

        let recovered = try await rollbackOwner.update {
            $0.localTextCleanupEnabled = false
        }
        guard case .ready(let recoveredValue) = recovered else {
            Issue.record("Expected a ready Settings value after retry.")
            return
        }
        #expect(recoveredValue.keepLatestResult)
        #expect(!recoveredValue.localTextCleanupEnabled)
        #expect(await rollbackRepository.storedValue() == recoveredValue)
    }

    @Test func settingsEditorsShareOneOwnerAndPreserveUnrelatedGroups()
        async throws {
        let initial = IOSAppSettings(
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "initial-transcription"
            ),
            textCorrectionConfiguration: TextCorrectionConfiguration(
                isEnabled: true,
                modelPreset: .balanced
            ),
            localTextCleanupEnabled: false,
            translationConfiguration: TranslationConfiguration(
                targetLanguage: .english
            ),
            keepLatestResult: false,
            voiceSessionPreferences: VoiceSessionPreferences(
                audioCuesEnabled: false,
                recordingStopTailDuration: .seconds1
            )
        )
        let repository = StateOwnerRepositoryFixture(
            initialValue: initial,
            suspendNextCommit: true
        )
        let owner = IOSAppSettingsStateOwner(
            load: { try await repository.load() },
            commit: { try await repository.commit($0) }
        )
        let firstSceneOwner = owner
        let secondSceneOwner = owner
        _ = try await owner.load()

        let transcription = TranscriptionConfiguration(
            model: "scene-one-transcription",
            language: .french
        )
        let translation = TranslationConfiguration(
            actionPreferenceEnabled: false,
            targetLanguage: .german
        )
        let firstSave = Task {
            try await firstSceneOwner.update {
                IOSAppSettingsEditorMutation.applyTranscription(
                    transcription,
                    to: &$0
                )
            }
        }
        try await stateOwnerEventually {
            await repository.commitCallCount() == 1
        }
        let secondSave = Task {
            try await secondSceneOwner.update {
                IOSAppSettingsEditorMutation.applyTranslation(
                    translation,
                    to: &$0
                )
            }
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(await repository.commitCallCount() == 1)

        await repository.resumeCommit()
        _ = try await firstSave.value
        _ = try await secondSave.value

        let stored = await repository.storedValue()
        #expect(stored.transcriptionConfiguration == transcription)
        #expect(stored.translationConfiguration == translation)
        #expect(
            stored.textCorrectionConfiguration
                == initial.textCorrectionConfiguration
        )
        #expect(
            stored.localTextCleanupEnabled
                == initial.localTextCleanupEnabled
        )
        #expect(stored.keepLatestResult == initial.keepLatestResult)
        #expect(
            stored.voiceSessionPreferences
                == initial.voiceSessionPreferences
        )
    }

    @Test func libraryPublishesCanonicalCommitAndRollsBackExactly()
        async throws {
        let commandID = UUID()
        let repository = StateOwnerRepositoryFixture(
            initialValue: IOSLibraryContent.defaults,
            commitFailures: [false, true, false],
            canonicalize: { content in
                IOSLibraryContent(
                    customDictionary: content.customDictionary,
                    emojiCommandsConfiguration: EmojiCommandsConfiguration(
                        isEnabled: content.emojiCommandsConfiguration.isEnabled,
                        enabledBuiltInSetIDs: content
                            .emojiCommandsConfiguration.enabledBuiltInSetIDs,
                        customCommands: EmojiCommandsConfiguration
                            .normalizedCustomCommands(
                                content.emojiCommandsConfiguration.customCommands
                            )
                    ),
                    replacementRules: content.replacementRules
                )
            }
        )
        let owner = IOSLibraryStateOwner(
            load: { try await repository.load() },
            commit: { try await repository.commit($0) }
        )
        _ = try await owner.load()

        let canonicalState = try await owner.update {
            $0.emojiCommandsConfiguration.customCommands = [
                CustomEmojiCommand(
                    id: commandID,
                    emoji: "  🚀  ",
                    command: "  Launch   now  ",
                    aliases: ["LAUNCH NOW", "  ship   it  "]
                ),
            ]
        }
        let canonical = IOSLibraryContent(
            emojiCommandsConfiguration: EmojiCommandsConfiguration(
                customCommands: [
                    CustomEmojiCommand(
                        id: commandID,
                        emoji: "🚀",
                        command: "Launch now",
                        aliases: ["ship it"]
                    ),
                ]
            )
        )
        let committedCandidates = await repository.committedCandidates()
        let firstCandidate = try #require(committedCandidates.first)
        #expect(firstCandidate != canonical)
        #expect(canonicalState == .ready(canonical))
        #expect(owner.state == .ready(canonical))
        #expect(await repository.storedValue() == canonical)

        await expectStateOwnerError(.saveFailed) {
            _ = try await owner.update {
                $0.customDictionary = CustomDictionary(
                    entries: ["Optimistic Candidate"]
                )
            }
        }
        #expect(
            owner.state
                == .saveFailed(lastDurableValue: canonical)
        )
        #expect(
            try await owner.confirmedValueForProviderAction() == canonical
        )
        #expect(await repository.storedValue() == canonical)

        let recoveredState = try await owner.update {
            $0.replacementRules = [
                TextReplacementRule(
                    search: "old",
                    replacement: "new"
                ),
            ]
        }
        guard case .ready(let recovered) = recoveredState else {
            Issue.record("Expected a ready Library value after retry.")
            return
        }
        #expect(recovered.customDictionary == canonical.customDictionary)
        #expect(recovered.replacementRules.count == 1)
        #expect(await repository.storedValue() == recovered)
    }

    @Test func cancellationBeforeLeaseDoesNoIOAndAcquiredCommitFinishes()
        async throws {
        let repository = StateOwnerRepositoryFixture(
            initialValue: IOSAppSettings.defaults,
            suspendNextCommit: true
        )
        let owner = IOSAppSettingsStateOwner(
            load: { try await repository.load() },
            commit: { try await repository.commit($0) }
        )
        _ = try await owner.load()

        let acquired = Task {
            try await owner.update {
                $0.keepLatestResult = false
            }
        }
        try await stateOwnerEventually {
            await repository.commitCallCount() == 1
        }
        let queued = Task {
            try await owner.update {
                $0.localTextCleanupEnabled = false
            }
        }
        for _ in 0..<20 { await Task.yield() }
        queued.cancel()

        await expectTaskStateOwnerError(
            .operationCancelledBeforeStart,
            task: queued
        )
        #expect(await repository.commitCallCount() == 1)

        acquired.cancel()
        await repository.resumeCommit()
        guard case .ready(let committed) = try await acquired.value else {
            Issue.record("Expected acquired commit to finish truthfully.")
            return
        }
        #expect(!committed.keepLatestResult)
        #expect(committed.localTextCleanupEnabled)
        #expect(await repository.storedValue() == committed)
        #expect(await repository.commitCallCount() == 1)
    }

    @Test func observableStatePublishesBeforeNextTransactionAcquiresLease()
        async throws {
        let committer = StateOwnerPublicationCommitter<IOSAppSettings>()
        let owner = IOSAppSettingsStateOwner(
            load: { .defaults },
            commit: { await committer.commit($0) }
        )
        _ = try await owner.load()

        let firstMutation = Task {
            try await owner.update {
                $0.keepLatestResult = false
            }
        }
        try await stateOwnerEventually {
            committer.callCount() == 1
        }
        let secondMutation = Task {
            try await owner.update {
                $0.localTextCleanupEnabled = false
            }
        }
        for _ in 0..<20 { await Task.yield() }

        // Resume without yielding MainActor. A transaction may release its
        // FIFO lease only after its observable snapshot reaches MainActor, so
        // the queued commit cannot begin while this thread is deliberately
        // keeping that publication pending.
        committer.resumeFirstCommit()
        #expect(committer.waitForFirstCommitResumption())
        #expect(!committer.waitForSecondCommitStart())
        #expect(committer.callCount() == 1)

        _ = try await firstMutation.value
        guard case .ready(let finalValue) = try await secondMutation.value else {
            Issue.record("Expected the second mutation to publish ready state.")
            return
        }
        #expect(!finalValue.keepLatestResult)
        #expect(!finalValue.localTextCleanupEnabled)
        #expect(owner.state == .ready(finalValue))
        #expect(committer.callCount() == 2)
    }

    @Test func stateValuesOwnersAndFailuresAreRedacted() async throws {
        let privateSettings = IOSAppSettings(
            transcriptionConfiguration: TranscriptionConfiguration(
                freeformPrompt: "SETTINGS-PRIVATE-CANARY"
            )
        )
        let privateLibrary = library(entry: "LIBRARY-PRIVATE-CANARY")
        let settingsOwner = IOSAppSettingsStateOwner(
            load: { privateSettings },
            commit: { $0 }
        )
        let libraryOwner = IOSLibraryStateOwner(
            load: { privateLibrary },
            commit: { $0 }
        )
        _ = try await settingsOwner.load()
        _ = try await libraryOwner.load()

        let renderings = [
            String(describing: settingsOwner.state),
            String(reflecting: settingsOwner.state),
            String(describing: libraryOwner.state),
            String(reflecting: libraryOwner.state),
            String(describing: settingsOwner),
            String(reflecting: libraryOwner),
            String(describing: IOSContainingAppStateOwnerError.saveFailed),
        ]
        #expect(
            renderings.allSatisfy {
                !$0.contains("SETTINGS-PRIVATE-CANARY")
                    && !$0.contains("LIBRARY-PRIVATE-CANARY")
            }
        )
        #expect(settingsOwner.state.customMirror.children.isEmpty)
        #expect(libraryOwner.state.customMirror.children.isEmpty)
        #expect(settingsOwner.customMirror.children.isEmpty)
        #expect(libraryOwner.customMirror.children.isEmpty)
    }
}

private enum StateOwnerRepositoryFixtureError: Error {
    case scriptedFailure
}

private actor StateOwnerRepositoryFixture<Value: Equatable & Sendable> {
    private var value: Value
    private var loadFailures: [Bool]
    private var commitFailures: [Bool]
    private var shouldSuspendNextLoad: Bool
    private var shouldSuspendNextCommit: Bool
    private let canonicalize: @Sendable (Value) -> Value

    private var loads = 0
    private var candidates: [Value] = []
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var commitContinuation: CheckedContinuation<Void, Never>?

    init(
        initialValue: Value,
        loadFailures: [Bool] = [],
        commitFailures: [Bool] = [],
        suspendNextLoad: Bool = false,
        suspendNextCommit: Bool = false,
        canonicalize: @escaping @Sendable (Value) -> Value = { $0 }
    ) {
        value = initialValue
        self.loadFailures = loadFailures
        self.commitFailures = commitFailures
        shouldSuspendNextLoad = suspendNextLoad
        shouldSuspendNextCommit = suspendNextCommit
        self.canonicalize = canonicalize
    }

    func load() async throws -> Value {
        loads += 1
        if shouldSuspendNextLoad {
            shouldSuspendNextLoad = false
            await withCheckedContinuation { continuation in
                loadContinuation = continuation
            }
        }
        if !loadFailures.isEmpty, loadFailures.removeFirst() {
            throw StateOwnerRepositoryFixtureError.scriptedFailure
        }
        return value
    }

    func commit(_ candidate: Value) async throws -> Value {
        candidates.append(candidate)
        if shouldSuspendNextCommit {
            shouldSuspendNextCommit = false
            await withCheckedContinuation { continuation in
                commitContinuation = continuation
            }
        }
        if !commitFailures.isEmpty, commitFailures.removeFirst() {
            throw StateOwnerRepositoryFixtureError.scriptedFailure
        }
        let committed = canonicalize(candidate)
        value = committed
        return committed
    }

    func resumeLoad() {
        let continuation = loadContinuation
        loadContinuation = nil
        continuation?.resume()
    }

    func resumeCommit() {
        let continuation = commitContinuation
        commitContinuation = nil
        continuation?.resume()
    }

    func loadCallCount() -> Int { loads }
    func commitCallCount() -> Int { candidates.count }
    func committedCandidates() -> [Value] { candidates }
    func storedValue() -> Value { value }
}

private actor StateOwnerProviderObservation<Value: Sendable> {
    private var storedValue: Value?

    func record(_ value: Value) {
        storedValue = value
    }

    func value() -> Value? { storedValue }
}

private final class StateOwnerPublicationCommitter<Value: Sendable>:
    @unchecked Sendable {
    private let lock = NSLock()
    private let firstCommitResumed = DispatchSemaphore(value: 0)
    private let secondCommitStarted = DispatchSemaphore(value: 0)
    private var calls = 0
    private var firstCommitContinuation: CheckedContinuation<Void, Never>?
    private var firstCommitResumeRequested = false

    func commit(_ value: Value) async -> Value {
        let callNumber = lock.withLock {
            calls += 1
            return calls
        }

        if callNumber == 2 {
            secondCommitStarted.signal()
        }

        if callNumber == 1 {
            await withCheckedContinuation { continuation in
                let resumeImmediately = lock.withLock {
                    if firstCommitResumeRequested {
                        return true
                    }
                    firstCommitContinuation = continuation
                    return false
                }
                if resumeImmediately {
                    continuation.resume()
                }
            }
            firstCommitResumed.signal()
        }
        return value
    }

    func resumeFirstCommit() {
        let continuation = lock.withLock {
            let continuation = firstCommitContinuation
            firstCommitContinuation = nil
            if continuation == nil {
                firstCommitResumeRequested = true
            }
            return continuation
        }
        continuation?.resume()
    }

    func callCount() -> Int {
        lock.withLock { calls }
    }

    func waitForFirstCommitResumption() -> Bool {
        firstCommitResumed.wait(timeout: .now() + 1) == .success
    }

    func waitForSecondCommitStart() -> Bool {
        secondCommitStarted.wait(timeout: .now() + 0.25) == .success
    }
}

@MainActor
private func expectStateOwnerError(
    _ expected: IOSContainingAppStateOwnerError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected a state-owner error.")
    } catch let error as IOSContainingAppStateOwnerError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected the typed state-owner error.")
    }
}

@MainActor
private func expectTaskStateOwnerError<Value: Sendable>(
    _ expected: IOSContainingAppStateOwnerError,
    task: Task<Value, Error>
) async {
    do {
        _ = try await task.value
        Issue.record("Expected a state-owner task error.")
    } catch let error as IOSContainingAppStateOwnerError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected the typed state-owner task error.")
    }
}

private func stateOwnerEventually(
    _ predicate: @escaping @Sendable () async -> Bool
) async throws {
    for _ in 0..<200 {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(2))
    }
    Issue.record("Timed out waiting for state-owner fixture progress.")
}

private func settings(model: String) -> IOSAppSettings {
    IOSAppSettings(
        transcriptionConfiguration: TranscriptionConfiguration(
            model: model
        )
    )
}

private func library(entry: String) -> IOSLibraryContent {
    IOSLibraryContent(
        customDictionary: CustomDictionary(entries: [entry])
    )
}
