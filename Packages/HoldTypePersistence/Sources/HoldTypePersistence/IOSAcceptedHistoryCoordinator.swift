import Darwin
import Foundation

/// Sealed proof that the containing-app coordinator observed every legacy
/// History owner as absent or empty before creating the physical 1/1 policy.
struct IOSHistoryPolicyBaselineAuthorization: Sendable {
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity

    init(
        acceptedHistory: IOSAcceptedHistoryGuardedBaselineEvidence,
        outbox: IOSAcceptedHistoryOutboxGuardedBaselineEvidence,
        delivery: IOSAcceptedOutputDeliveryGuardedBaselineEvidence,
        failedHistory: IOSFailedHistoryGuardedBaselineEvidence
    ) throws {
        guard acceptedHistory.capabilityOwnerIdentity
                == outbox.capabilityOwnerIdentity,
              acceptedHistory.capabilityOwnerIdentity
                == delivery.capabilityOwnerIdentity,
              acceptedHistory.capabilityOwnerIdentity
                == failedHistory.capabilityOwnerIdentity else {
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }
        capabilityOwnerIdentity = acceptedHistory.capabilityOwnerIdentity
    }

    init(
        testingToken: Void,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
            IOSAcceptedHistoryCapabilityOwnerIdentity()
    ) {
        _ = testingToken
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
    }
}

extension IOSHistoryPolicyBaselineAuthorization: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSHistoryPolicyBaselineAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

public enum IOSAcceptedHistoryCoordinatorError: Error, Equatable, Sendable {
    case cancelledBeforeOperation
    case reentrantOperation
    case repositoryIdentityConflict
    case localRecoveryPending
}

actor IOSAcceptedHistoryBaselineRecoveryState {
    private var isRequired = false

    func value() -> Bool { isRequired }

    func requireRecovery() {
        isRequired = true
    }

    func clear() {
        isRequired = false
    }
}

final class IOSAcceptedHistoryCoordinatorRepositoryIdentityState:
    @unchecked Sendable {
    private let lock = NSLock()
    private var conflicted = false

    var isConflicted: Bool { lock.withLock { conflicted } }

    func markConflicted() {
        lock.withLock { conflicted = true }
    }
}

final class IOSAcceptedHistoryCoordinatorProcessContext: Sendable {
    let applicationSupportDirectoryURL: URL
    let repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    let repositoryGuard: IOSAcceptedHistoryCoordinatorRepositoryGuard
    let operationGate: IOSPersistenceOperationGate
    let pendingRecordingLiveOwnerRegistry:
        IOSPendingRecordingLiveOwnerRegistry
    let pendingRecordingStoreIdentity: IOSPendingRecordingStoreIdentity
    let pendingRecordingMediaValidationWorkerGate:
        AudioToolboxMediaValidationWorkerGate
    let foregroundVoiceCaptureSourceOwner:
        IOSForegroundVoiceCaptureSourceOwner
    let failedHistoryMutationInterlock: IOSFailedHistoryMutationInterlock
    let policyStore: IOSHistoryPolicyStore
    let pendingRecordingStore: IOSPendingRecordingStore
    let acceptedHistoryStore: IOSAcceptedHistoryStore
    let failedHistoryStore: IOSFailedHistoryStore
    let outboxStore: IOSAcceptedHistoryOutboxStore
    let deliveryStore: IOSAcceptedOutputDeliveryStore
    let baselineRecoveryState: IOSAcceptedHistoryBaselineRecoveryState
    let acceptanceState: IOSAcceptedHistoryAcceptanceOperationState
    let pendingReplacementState:
        IOSAcceptedHistoryPendingReplacementOperationState
    let outboxWorkerState: IOSAcceptedHistoryOutboxWorkerOperationState
    let policyCutoverState: IOSHistoryPolicyCutoverOperationState
    let failedHistoryTransferState:
        IOSFailedHistoryTransferOperationState
    let failedHistoryAudioCleanupState:
        IOSFailedHistoryAudioCleanupOperationState
    let failedHistoryRetryState: IOSFailedHistoryRetryLiveOwnerState
    let foregroundVoicePersistenceState:
        IOSForegroundVoicePersistenceOperationState
    let providerConsentOwner: IOSProviderConsentOwner
    let providerConsentAuthorizationGate:
        IOSProviderConsentAuthorizationGate
    let ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity
    let repositoryIdentityState:
        IOSAcceptedHistoryCoordinatorRepositoryIdentityState

    init(
        applicationSupportDirectoryURL: URL,
        repositoryBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        retryRecoveryScanRequired: Bool
    ) {
        let capabilityOwnerIdentity =
            IOSAcceptedHistoryCapabilityOwnerIdentity()
        let operationGate = IOSPersistenceOperationGate()
        let pendingRecordingLiveOwnerRegistry =
            IOSPendingRecordingLiveOwnerRegistry()
        let pendingRecordingStoreIdentity =
            IOSPendingRecordingStoreIdentity()
        let pendingRecordingMediaValidationWorkerGate =
            AudioToolboxMediaValidationWorkerGate()
        let failedHistoryMutationInterlock =
            IOSFailedHistoryMutationInterlock(
                retryRecoveryScanRequired: retryRecoveryScanRequired
            )
        let failedHistoryRetryState =
            IOSFailedHistoryRetryLiveOwnerState()
        let foregroundVoicePersistenceState =
            IOSForegroundVoicePersistenceOperationState()
        let providerConsentAuthorizationGate =
            IOSProviderConsentAuthorizationGate()
        let deliveryStoreIdentity = IOSAcceptedOutputDeliveryStoreIdentity()
        let outboxStoreIdentity = IOSAcceptedHistoryOutboxStoreIdentity()
        let repositoryIdentityState =
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState()
        let repositoryGuard = IOSAcceptedHistoryCoordinatorRepositoryGuard(
            expectedBinding: repositoryBinding,
            repositoryIdentityState: repositoryIdentityState
        )
        let providerConsentOwner = IOSProviderConsentOwner(
            journal: FoundationIOSProviderConsentJournalRepository(
                applicationSupportDirectoryURL:
                    applicationSupportDirectoryURL,
                repositoryGuard: repositoryGuard
            ),
            currentDisclosureVersion:
                IOSProviderConsentCoordinator.currentDisclosureVersion,
            expectedRepositoryRootIdentity:
                repositoryBinding.physicalRootIdentity,
            repositoryAdmissionRevalidation: {
                try repositoryGuard.revalidate().physicalRootIdentity
            }
        )
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
        self.repositoryBinding = repositoryBinding
        self.repositoryGuard = repositoryGuard
        self.operationGate = operationGate
        self.pendingRecordingLiveOwnerRegistry =
            pendingRecordingLiveOwnerRegistry
        self.pendingRecordingStoreIdentity = pendingRecordingStoreIdentity
        self.pendingRecordingMediaValidationWorkerGate =
            pendingRecordingMediaValidationWorkerGate
        foregroundVoiceCaptureSourceOwner =
            IOSForegroundVoiceCaptureSourceOwner(
                applicationSupportDirectoryURL:
                    applicationSupportDirectoryURL,
                mediaValidationWorkerGate:
                    pendingRecordingMediaValidationWorkerGate
            )
        self.failedHistoryMutationInterlock =
            failedHistoryMutationInterlock
        ownerIdentity = capabilityOwnerIdentity
        policyStore = IOSHistoryPolicyStore(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            capabilityOwnerIdentity: capabilityOwnerIdentity,
            repositoryGuard: repositoryGuard
        )
        let failedHistoryStore = IOSFailedHistoryStore(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            capabilityOwnerIdentity: capabilityOwnerIdentity,
            expectedPendingStoreIdentity: pendingRecordingStoreIdentity,
            expectedDeliveryStoreIdentity: deliveryStoreIdentity,
            retryLiveOwnerState: failedHistoryRetryState,
            repositoryGuard: repositoryGuard,
            mutationInterlock: failedHistoryMutationInterlock
        )
        self.failedHistoryStore = failedHistoryStore
        let pendingRecordingStore = IOSPendingRecordingStore(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            capabilityOwnerIdentity: capabilityOwnerIdentity,
            storeIdentity: pendingRecordingStoreIdentity,
            operationGate: operationGate,
            liveOwnerRegistry: pendingRecordingLiveOwnerRegistry,
            failedHistoryRetryState: failedHistoryRetryState,
            mediaValidationWorkerGate:
                pendingRecordingMediaValidationWorkerGate,
            repositoryGuard: repositoryGuard,
            failedHistoryMutationInterlock:
                failedHistoryMutationInterlock,
            failedOwnershipInspector: failedHistoryStore
        )
        self.pendingRecordingStore = pendingRecordingStore
        acceptedHistoryStore = IOSAcceptedHistoryStore(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            capabilityOwnerIdentity: capabilityOwnerIdentity,
            repositoryGuard: repositoryGuard
        )
        outboxStore = IOSAcceptedHistoryOutboxStore(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            deliveryStoreIdentity: deliveryStoreIdentity,
            storeIdentity: outboxStoreIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity,
            repositoryGuard: repositoryGuard
        )
        deliveryStore = IOSAcceptedOutputDeliveryStore(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            storeIdentity: deliveryStoreIdentity,
            outboxStoreIdentity: outboxStoreIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity,
            failedHistoryMutationInterlock:
                failedHistoryMutationInterlock,
            repositoryGuard: repositoryGuard
        )
        baselineRecoveryState = IOSAcceptedHistoryBaselineRecoveryState()
        acceptanceState = IOSAcceptedHistoryAcceptanceOperationState()
        pendingReplacementState =
            IOSAcceptedHistoryPendingReplacementOperationState()
        outboxWorkerState = IOSAcceptedHistoryOutboxWorkerOperationState()
        policyCutoverState = IOSHistoryPolicyCutoverOperationState()
        failedHistoryTransferState =
            IOSFailedHistoryTransferOperationState()
        failedHistoryAudioCleanupState =
            IOSFailedHistoryAudioCleanupOperationState()
        self.failedHistoryRetryState = failedHistoryRetryState
        self.foregroundVoicePersistenceState =
            foregroundVoicePersistenceState
        self.providerConsentOwner = providerConsentOwner
        self.providerConsentAuthorizationGate =
            providerConsentAuthorizationGate
        self.repositoryIdentityState = repositoryIdentityState

        let pendingGateBindingAccepted =
            pendingRecordingStore.bindOperationGateIdentity(
                operationGate.identity
            )
        let pendingFailedBindingAccepted =
            failedHistoryStore.bindExpectedPendingStoreIdentity(
                pendingRecordingStoreIdentity
            )
        let failedGateBindingAccepted =
            failedHistoryStore.bindOperationGateIdentity(
                operationGate.identity
            )
        let failedRetryStateBindingAccepted =
            failedHistoryStore.bindRetryLiveOwnerStateIdentity(
                failedHistoryRetryState.identity
            )
        let failedDeliveryBindingAccepted =
            failedHistoryStore.bindExpectedDeliveryStoreIdentity(
                deliveryStoreIdentity
            )
        let retryProviderBindingAccepted = repositoryBinding
            .physicalRootIdentity.map {
                failedHistoryRetryState.bindProviderRegistration(
                    failedStoreIdentity: failedHistoryStore.storeIdentity,
                    ownerIdentity: capabilityOwnerIdentity,
                    physicalRootIdentity: $0
                )
            } ?? false
        let outboxGateBindingAccepted =
            outboxStore.bindOperationGateIdentity(operationGate.identity)
        let deliveryGateBindingAccepted =
            deliveryStore.bindOperationGateIdentity(operationGate.identity)
        let deliveryFailedInterlockBindingAccepted =
            deliveryStore.bindFailedHistoryMutationInterlock(
                failedHistoryMutationInterlock
            )
        if !pendingGateBindingAccepted
            || !pendingFailedBindingAccepted
            || !failedGateBindingAccepted
            || !failedRetryStateBindingAccepted
            || !failedDeliveryBindingAccepted
            || !retryProviderBindingAccepted
            || !outboxGateBindingAccepted
            || !deliveryGateBindingAccepted
            || !deliveryFailedInterlockBindingAccepted {
            repositoryIdentityState.markConflicted()
        }
    }
}

struct IOSAcceptedHistoryCoordinatorRepositoryBinding: Equatable, Sendable {
    fileprivate let resolvedPath: String
    fileprivate let device: dev_t?
    fileprivate let inode: ino_t?

    var physicalRootIdentity: IOSPersistenceRepositoryRootIdentity? {
        guard let device, let inode else { return nil }
        return IOSPersistenceRepositoryRootIdentity(
            device: device,
            inode: inode
        )
    }
}

extension IOSAcceptedHistoryCoordinatorRepositoryBinding:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedHistoryCoordinatorRepositoryBinding(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

final class IOSAcceptedHistoryCoordinatorProcessContextRegistry:
    @unchecked Sendable {
    static let shared =
        IOSAcceptedHistoryCoordinatorProcessContextRegistry(
            retryRecoveryScanRequiredOnContextCreation: true
        )

    private let retryRecoveryScanRequiredOnContextCreation: Bool

    private struct PhysicalRootKey: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    private struct RootResolution {
        let lexicalKeys: [String]
        let resolvedRoot: URL
        let physicalKey: PhysicalRootKey?
        let isSymbolicLink: Bool

        var binding: IOSAcceptedHistoryCoordinatorRepositoryBinding {
            IOSAcceptedHistoryCoordinatorRepositoryBinding(
                resolvedPath: resolvedRoot.path,
                device: physicalKey?.device,
                inode: physicalKey?.inode
            )
        }
    }

    private struct ContextCandidates {
        var valid: [IOSAcceptedHistoryCoordinatorProcessContext] = []
        var invalidLexical: [IOSAcceptedHistoryCoordinatorProcessContext] = []
        var invalidPhysical: [IOSAcceptedHistoryCoordinatorProcessContext] = []
        var physicalConflict = false
    }

    private struct RegisteredInputRoot {
        let url: URL
        let context: IOSAcceptedHistoryCoordinatorProcessContext
        let wasSymbolicLink: Bool
    }

    private let lock = NSLock()
    private var contextsByLexicalRoot:
        [String: IOSAcceptedHistoryCoordinatorProcessContext] = [:]
    private var contextsByPhysicalRoot:
        [PhysicalRootKey: IOSAcceptedHistoryCoordinatorProcessContext] = [:]
    private var conflictedPhysicalRoots: Set<PhysicalRootKey> = []
    private var registeredInputRoots: [RegisteredInputRoot] = []

    init(
        retryRecoveryScanRequiredOnContextCreation: Bool = false
    ) {
        self.retryRecoveryScanRequiredOnContextCreation =
            retryRecoveryScanRequiredOnContextCreation
    }

    func context(
        for applicationSupportDirectoryURL: URL
    ) -> IOSAcceptedHistoryCoordinatorProcessContext {
        return lock.withLock {
            poisonConvergedRegisteredContexts()
            let resolution = rootResolution(
                for: applicationSupportDirectoryURL
            )
            var candidates = contextCandidates(for: resolution)
            for invalidContext in candidates.invalidLexical
                where invalidContext.applicationSupportDirectoryURL.absoluteURL
                    .standardizedFileURL.path == resolution.resolvedRoot.path {
                tombstoneBindingChange(
                    from: invalidContext.repositoryBinding,
                    to: resolution,
                    including: [invalidContext]
                )
                candidates.physicalConflict = true
            }
            if !candidates.invalidLexical.isEmpty {
                markConflicted(candidates.invalidLexical)
            }
            if candidates.physicalConflict {
                markConflicted(candidates.invalidPhysical + candidates.valid)
            }
            if candidates.valid.count > 1 {
                markConflicted(candidates.valid)
                let context = candidates.valid[0]
                rememberInputRoot(
                    applicationSupportDirectoryURL,
                    context: context
                )
                return context
            }
            if let context = candidates.valid.first {
                associate(
                    context,
                    with: resolution
                )
                rememberInputRoot(
                    applicationSupportDirectoryURL,
                    context: context
                )
                return context
            }
            let context = IOSAcceptedHistoryCoordinatorProcessContext(
                applicationSupportDirectoryURL: resolution.resolvedRoot,
                repositoryBinding: resolution.binding,
                retryRecoveryScanRequired:
                    retryRecoveryScanRequiredOnContextCreation
            )
            let canonicalRegistration =
                IOSAcceptedHistoryCoordinatorRepositoryRegistration(
                    registry: self,
                    context: context,
                    applicationSupportDirectoryURL: resolution.resolvedRoot
                )
            if !context.repositoryGuard.bind(canonicalRegistration) {
                context.repositoryIdentityState.markConflicted()
            }
            if resolution.physicalKey == nil {
                context.repositoryIdentityState.markConflicted()
            }
            if candidates.physicalConflict {
                markConflicted(candidates.invalidPhysical + [context])
            }
            associate(context, with: resolution)
            rememberInputRoot(
                applicationSupportDirectoryURL,
                context: context
            )
            return context
        }
    }

    @discardableResult
    func revalidate(
        context: IOSAcceptedHistoryCoordinatorProcessContext,
        for applicationSupportDirectoryURL: URL,
        expectedBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding? = nil
    ) -> IOSAcceptedHistoryCoordinatorRepositoryBinding {
        lock.withLock {
            let resolution = rootResolution(
                for: applicationSupportDirectoryURL
            )
            poisonConvergedRegisteredContexts()
            guard resolution.physicalKey != nil else {
                if let expectedBinding {
                    tombstoneBindingChange(
                        from: expectedBinding,
                        to: resolution,
                        including: [context]
                    )
                } else {
                    context.repositoryIdentityState.markConflicted()
                }
                return resolution.binding
            }
            let candidates = contextCandidates(for: resolution)
            markConflicted(candidates.invalidLexical)
            if candidates.physicalConflict {
                markConflicted(
                    candidates.invalidPhysical + candidates.valid + [context]
                )
                return resolution.binding
            }
            if !contextStillAddresses(context, resolution: resolution) {
                context.repositoryIdentityState.markConflicted()
                return resolution.binding
            }
            if let expectedBinding,
               expectedBinding != resolution.binding {
                tombstoneBindingChange(
                    from: expectedBinding,
                    to: resolution,
                    including: candidates.valid + [context]
                )
                return resolution.binding
            }
            var conflicts: [IOSAcceptedHistoryCoordinatorProcessContext] = []
            for candidate in candidates.valid where candidate !== context {
                append(context, unlessPresentIn: &conflicts)
                append(candidate, unlessPresentIn: &conflicts)
            }
            guard conflicts.isEmpty else {
                markConflicted(conflicts)
                return resolution.binding
            }
            associate(context, with: resolution)
            return resolution.binding
        }
    }

    private func associate(
        _ context: IOSAcceptedHistoryCoordinatorProcessContext,
        with resolution: RootResolution
    ) {
        for lexicalKey in resolution.lexicalKeys {
            contextsByLexicalRoot[lexicalKey] = context
        }
        if let physicalKey = resolution.physicalKey {
            contextsByPhysicalRoot[physicalKey] = context
        }
    }

    private func contextCandidates(
        for resolution: RootResolution
    ) -> ContextCandidates {
        var candidates = ContextCandidates()
        for lexicalKey in resolution.lexicalKeys {
            guard let context = contextsByLexicalRoot[lexicalKey] else {
                continue
            }
            if contextStillAddresses(context, resolution: resolution) {
                append(context, unlessPresentIn: &candidates.valid)
            } else {
                append(context, unlessPresentIn: &candidates.invalidLexical)
                contextsByLexicalRoot.removeValue(forKey: lexicalKey)
            }
        }
        if let physicalKey = resolution.physicalKey {
            if conflictedPhysicalRoots.contains(physicalKey) {
                candidates.physicalConflict = true
                if let context = contextsByPhysicalRoot[physicalKey] {
                    append(
                        context,
                        unlessPresentIn: &candidates.invalidPhysical
                    )
                }
            } else if let context = contextsByPhysicalRoot[physicalKey] {
                if contextStillAddresses(context, resolution: resolution) {
                    append(context, unlessPresentIn: &candidates.valid)
                } else {
                    append(
                        context,
                        unlessPresentIn: &candidates.invalidPhysical
                    )
                    conflictedPhysicalRoots.insert(physicalKey)
                    candidates.physicalConflict = true
                }
            }
        }
        return candidates
    }

    private func contextStillAddresses(
        _ context: IOSAcceptedHistoryCoordinatorProcessContext,
        resolution: RootResolution
    ) -> Bool {
        let currentRoot = context.applicationSupportDirectoryURL.absoluteURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard let pinnedPhysicalKey = physicalRootKey(
            for: context.repositoryBinding
        ),
        resolution.physicalKey == pinnedPhysicalKey,
        physicalRootKey(for: currentRoot) == pinnedPhysicalKey else {
            return false
        }
        return true
    }

    private func rootResolution(
        for applicationSupportDirectoryURL: URL
    ) -> RootResolution {
        let lexicalRoot = applicationSupportDirectoryURL.absoluteURL
            .standardizedFileURL
        let resolvedRoot = lexicalRoot.resolvingSymlinksInPath()
        let lexicalKeys = lexicalRoot.path == resolvedRoot.path
            ? [lexicalRoot.path]
            : [lexicalRoot.path, resolvedRoot.path]
        return RootResolution(
            lexicalKeys: lexicalKeys,
            resolvedRoot: resolvedRoot,
            physicalKey: physicalRootKey(for: resolvedRoot),
            isSymbolicLink: pathIsSymbolicLink(lexicalRoot)
        )
    }

    private func append(
        _ context: IOSAcceptedHistoryCoordinatorProcessContext,
        unlessPresentIn contexts: inout [IOSAcceptedHistoryCoordinatorProcessContext]
    ) {
        guard !contexts.contains(where: { $0 === context }) else { return }
        contexts.append(context)
    }

    private func markConflicted(
        _ contexts: [IOSAcceptedHistoryCoordinatorProcessContext]
    ) {
        var marked: [IOSAcceptedHistoryCoordinatorProcessContext] = []
        for context in contexts {
            guard !marked.contains(where: { $0 === context }) else { continue }
            context.repositoryIdentityState.markConflicted()
            marked.append(context)
        }
    }

    private func tombstoneBindingChange(
        from expectedBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        to resolution: RootResolution,
        including contexts: [IOSAcceptedHistoryCoordinatorProcessContext]
    ) {
        var involved = contexts
        if let expectedPhysicalKey = physicalRootKey(
            for: expectedBinding
        ) {
            conflictedPhysicalRoots.insert(expectedPhysicalKey)
            if let context = contextsByPhysicalRoot[expectedPhysicalKey] {
                append(context, unlessPresentIn: &involved)
            }
        }
        if let currentPhysicalKey = resolution.physicalKey {
            conflictedPhysicalRoots.insert(currentPhysicalKey)
            if let context = contextsByPhysicalRoot[currentPhysicalKey] {
                append(context, unlessPresentIn: &involved)
            }
        }
        markConflicted(involved)
    }

    private func rememberInputRoot(
        _ applicationSupportDirectoryURL: URL,
        context: IOSAcceptedHistoryCoordinatorProcessContext
    ) {
        let url = applicationSupportDirectoryURL.absoluteURL
            .standardizedFileURL
        guard !registeredInputRoots.contains(where: {
            $0.url.path == url.path && $0.context === context
        }) else {
            return
        }
        registeredInputRoots.append(
            RegisteredInputRoot(
                url: url,
                context: context,
                wasSymbolicLink: pathIsSymbolicLink(url)
            )
        )
    }

    private func poisonConvergedRegisteredContexts() {
        var contextsByCurrentPhysicalRoot:
            [PhysicalRootKey: [IOSAcceptedHistoryCoordinatorProcessContext]] = [:]
        for registration in registeredInputRoots {
            let resolution = rootResolution(for: registration.url)
            guard let physicalKey = resolution.physicalKey else {
                registration.context.repositoryIdentityState.markConflicted()
                continue
            }
            guard contextStillAddresses(
                registration.context,
                resolution: resolution
            ) else {
                let canonicalContextPath = registration.context
                    .applicationSupportDirectoryURL.absoluteURL
                    .standardizedFileURL.path
                if resolution.resolvedRoot.path == canonicalContextPath
                    || !registration.wasSymbolicLink
                    || !resolution.isSymbolicLink {
                    tombstoneBindingChange(
                        from: registration.context.repositoryBinding,
                        to: resolution,
                        including: [registration.context]
                    )
                } else {
                    registration.context.repositoryIdentityState
                        .markConflicted()
                }
                continue
            }
            var contexts = contextsByCurrentPhysicalRoot[physicalKey] ?? []
            append(registration.context, unlessPresentIn: &contexts)
            contextsByCurrentPhysicalRoot[physicalKey] = contexts
        }

        for (physicalKey, contexts) in contextsByCurrentPhysicalRoot
            where contexts.count > 1 {
            conflictedPhysicalRoots.insert(physicalKey)
            markConflicted(contexts)
        }
    }

    private func physicalRootKey(
        for binding: IOSAcceptedHistoryCoordinatorRepositoryBinding
    ) -> PhysicalRootKey? {
        guard let device = binding.device,
              let inode = binding.inode else {
            return nil
        }
        return PhysicalRootKey(device: device, inode: inode)
    }

    private func pathIsSymbolicLink(_ url: URL) -> Bool {
        var status = stat()
        let didRead = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return Darwin.lstat(path, &status) == 0
        }
        return didRead && status.st_mode & S_IFMT == S_IFLNK
    }

    private func physicalRootKey(
        for resolvedRoot: URL
    ) -> PhysicalRootKey? {
        var status = stat()
        let hasPhysicalIdentity = resolvedRoot
            .withUnsafeFileSystemRepresentation { path in
                guard let path else { return false }
                return Darwin.lstat(path, &status) == 0
            }
        guard hasPhysicalIdentity else { return nil }
        return PhysicalRootKey(
            device: status.st_dev,
            inode: status.st_ino
        )
    }
}

struct IOSAcceptedHistoryCoordinatorRepositoryRegistration: Sendable {
    let registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry
    let context: IOSAcceptedHistoryCoordinatorProcessContext
    let applicationSupportDirectoryURL: URL

    init(
        registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry,
        context: IOSAcceptedHistoryCoordinatorProcessContext,
        applicationSupportDirectoryURL: URL
    ) {
        self.registry = registry
        self.context = context
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
            .absoluteURL
            .standardizedFileURL
    }

    func revalidate(
        expectedBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding? = nil
    ) -> IOSAcceptedHistoryCoordinatorRepositoryBinding {
        registry.revalidate(
            context: context,
            for: applicationSupportDirectoryURL,
            expectedBinding: expectedBinding ?? context.repositoryBinding
        )
    }
}

enum IOSAcceptedHistoryCoordinatorRepositoryGuardError:
    Error,
    Equatable,
    Sendable {
    case unbound
    case repositoryIdentityConflict
}

final class IOSAcceptedHistoryCoordinatorRepositoryGuard:
    @unchecked Sendable {
    private let lock = NSLock()
    private let expectedBinding:
        IOSAcceptedHistoryCoordinatorRepositoryBinding
    private let repositoryIdentityState:
        IOSAcceptedHistoryCoordinatorRepositoryIdentityState
    private var registration:
        IOSAcceptedHistoryCoordinatorRepositoryRegistration?

    init(
        expectedBinding: IOSAcceptedHistoryCoordinatorRepositoryBinding,
        repositoryIdentityState:
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState
    ) {
        self.expectedBinding = expectedBinding
        self.repositoryIdentityState = repositoryIdentityState
    }

    func bind(
        _ registration: IOSAcceptedHistoryCoordinatorRepositoryRegistration
    ) -> Bool {
        lock.withLock {
            guard self.registration == nil else { return false }
            self.registration = registration
            return true
        }
    }

    func revalidate(
        expectedBinding:
            IOSAcceptedHistoryCoordinatorRepositoryBinding? = nil
    ) throws -> IOSAcceptedHistoryCoordinatorRepositoryBinding {
        guard let registration = lock.withLock({ registration }) else {
            throw IOSAcceptedHistoryCoordinatorRepositoryGuardError.unbound
        }
        let current = registration.revalidate(
            expectedBinding: expectedBinding ?? self.expectedBinding
        )
        guard !repositoryIdentityState.isConflicted else {
            throw IOSAcceptedHistoryCoordinatorRepositoryGuardError
                .repositoryIdentityConflict
        }
        return current
    }

    var expectedPhysicalRootIdentity:
        IOSPersistenceRepositoryRootIdentity? {
        expectedBinding.physicalRootIdentity
    }

    func invalidate() {
        repositoryIdentityState.markConflicted()
    }
}

extension IOSAcceptedHistoryCoordinatorError: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSAcceptedHistoryCoordinatorError(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Opaque acceptance-time History decision. Public callers can carry this
/// value into delivery preparation but cannot choose a policy generation or
/// construct a pending marker themselves.
public struct IOSAcceptedOutputHistoryCapture: Equatable, Sendable {
    let policyReceipt: IOSHistoryPolicyReceipt
    let ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity
    let historyWrite: IOSAcceptedOutputHistoryWrite?

    init(
        policyReceipt: IOSHistoryPolicyReceipt,
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity,
        historyWrite: IOSAcceptedOutputHistoryWrite?
    ) {
        self.policyReceipt = policyReceipt
        self.ownerIdentity = ownerIdentity
        self.historyWrite = historyWrite
    }

    init(
        testingPolicyReceipt policyReceipt: IOSHistoryPolicyReceipt,
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity? = nil,
        historyWrite: IOSAcceptedOutputHistoryWrite?
    ) {
        self.init(
            policyReceipt: policyReceipt,
            ownerIdentity: ownerIdentity
                ?? policyReceipt.capabilityOwnerIdentity,
            historyWrite: historyWrite
        )
    }
}

extension IOSAcceptedOutputHistoryCapture: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSAcceptedOutputHistoryCapture(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

public actor IOSAcceptedHistoryCoordinator {
    enum CaptureOperationError: Error, Sendable {
        case baselineCommitUncertain
        case definitiveBaselineConflict
    }

    let policyStore: IOSHistoryPolicyStore
    let pendingRecordingStore: IOSPendingRecordingStore?
    let acceptedHistoryStore: IOSAcceptedHistoryStore
    let failedHistoryStore: IOSFailedHistoryStore
    let outboxStore: IOSAcceptedHistoryOutboxStore
    let deliveryStore: IOSAcceptedOutputDeliveryStore
    let operationGate: IOSPersistenceOperationGate
    let baselineRecoveryState: IOSAcceptedHistoryBaselineRecoveryState
    let acceptanceState: IOSAcceptedHistoryAcceptanceOperationState
    let pendingReplacementState:
        IOSAcceptedHistoryPendingReplacementOperationState
    let outboxWorkerState: IOSAcceptedHistoryOutboxWorkerOperationState
    let policyCutoverState: IOSHistoryPolicyCutoverOperationState
    let failedHistoryTransferState:
        IOSFailedHistoryTransferOperationState
    let failedHistoryAudioCleanupState:
        IOSFailedHistoryAudioCleanupOperationState
    let failedHistoryRetryState: IOSFailedHistoryRetryLiveOwnerState
    let foregroundVoicePersistenceState:
        IOSForegroundVoicePersistenceOperationState
    let failedHistoryMutationInterlock: IOSFailedHistoryMutationInterlock
    let ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity
    let repositoryIdentityState:
        IOSAcceptedHistoryCoordinatorRepositoryIdentityState
    let repositoryRegistration:
        IOSAcceptedHistoryCoordinatorRepositoryRegistration?

    public init(applicationSupportDirectoryURL: URL) {
        self.init(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            registry: .shared
        )
    }

    init(
        applicationSupportDirectoryURL: URL,
        registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry
    ) {
        let context = registry.context(
            for: applicationSupportDirectoryURL
        )
        policyStore = context.policyStore
        pendingRecordingStore = context.pendingRecordingStore
        acceptedHistoryStore = context.acceptedHistoryStore
        failedHistoryStore = context.failedHistoryStore
        outboxStore = context.outboxStore
        deliveryStore = context.deliveryStore
        operationGate = context.operationGate
        baselineRecoveryState = context.baselineRecoveryState
        acceptanceState = context.acceptanceState
        pendingReplacementState = context.pendingReplacementState
        outboxWorkerState = context.outboxWorkerState
        policyCutoverState = context.policyCutoverState
        failedHistoryTransferState = context.failedHistoryTransferState
        failedHistoryAudioCleanupState =
            context.failedHistoryAudioCleanupState
        failedHistoryRetryState = context.failedHistoryRetryState
        foregroundVoicePersistenceState =
            context.foregroundVoicePersistenceState
        failedHistoryMutationInterlock =
            context.failedHistoryMutationInterlock
        ownerIdentity = context.ownerIdentity
        repositoryIdentityState = context.repositoryIdentityState
        repositoryRegistration =
            IOSAcceptedHistoryCoordinatorRepositoryRegistration(
                registry: registry,
                context: context,
                applicationSupportDirectoryURL:
                    applicationSupportDirectoryURL
            )
    }

    init(
        policyStore: IOSHistoryPolicyStore,
        acceptedHistoryStore: IOSAcceptedHistoryStore,
        failedHistoryStore: IOSFailedHistoryStore,
        pendingRecordingStore: IOSPendingRecordingStore? = nil,
        outboxStore: IOSAcceptedHistoryOutboxStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore
    ) {
        let capabilityOwnerIdentity = policyStore.capabilityOwnerIdentity
        let identityState =
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState()
        let operationGate = IOSPersistenceOperationGate()
        let failedHistoryRetryState =
            failedHistoryStore.retryLiveOwnerState
        let pendingGateBindingAccepted = pendingRecordingStore?
            .bindOperationGateIdentity(operationGate.identity) ?? true
        let pendingFailedBindingAccepted = pendingRecordingStore.map {
            failedHistoryStore.bindExpectedPendingStoreIdentity(
                $0.storeIdentity
            )
        } ?? true
        let failedGateBindingAccepted =
            failedHistoryStore.bindOperationGateIdentity(
                operationGate.identity
            )
        let failedRetryStateBindingAccepted =
            failedHistoryStore.bindRetryLiveOwnerStateIdentity(
                failedHistoryRetryState.identity
            )
        let failedDeliveryBindingAccepted =
            failedHistoryStore.bindExpectedDeliveryStoreIdentity(
                deliveryStore.storeIdentity
            )
        let outboxGateBindingAccepted =
            outboxStore.bindOperationGateIdentity(operationGate.identity)
        let deliveryGateBindingAccepted =
            deliveryStore.bindOperationGateIdentity(operationGate.identity)
        let deliveryFailedInterlockBindingAccepted =
            deliveryStore.bindFailedHistoryMutationInterlock(
                failedHistoryStore.mutationInterlock
            )
        self.policyStore = policyStore
        self.pendingRecordingStore = pendingRecordingStore
        self.acceptedHistoryStore = acceptedHistoryStore
        self.failedHistoryStore = failedHistoryStore
        self.outboxStore = outboxStore
        self.deliveryStore = deliveryStore
        self.operationGate = operationGate
        baselineRecoveryState = IOSAcceptedHistoryBaselineRecoveryState()
        acceptanceState = IOSAcceptedHistoryAcceptanceOperationState()
        pendingReplacementState =
            IOSAcceptedHistoryPendingReplacementOperationState()
        outboxWorkerState = IOSAcceptedHistoryOutboxWorkerOperationState()
        policyCutoverState = IOSHistoryPolicyCutoverOperationState()
        failedHistoryTransferState =
            IOSFailedHistoryTransferOperationState()
        failedHistoryAudioCleanupState =
            IOSFailedHistoryAudioCleanupOperationState()
        self.failedHistoryRetryState = failedHistoryRetryState
        foregroundVoicePersistenceState =
            IOSForegroundVoicePersistenceOperationState()
        failedHistoryMutationInterlock =
            failedHistoryStore.mutationInterlock
        ownerIdentity = capabilityOwnerIdentity
        repositoryIdentityState = identityState
        repositoryRegistration = nil
        if !pendingGateBindingAccepted
            || !pendingFailedBindingAccepted
            || !failedGateBindingAccepted
            || !failedRetryStateBindingAccepted
            || !failedDeliveryBindingAccepted
            || !outboxGateBindingAccepted
            || !deliveryGateBindingAccepted
            || !deliveryFailedInterlockBindingAccepted
            || (pendingRecordingStore.map {
                $0.capabilityOwnerIdentity != capabilityOwnerIdentity
            } ?? false)
            || acceptedHistoryStore.capabilityOwnerIdentity
                != capabilityOwnerIdentity
            || failedHistoryStore.capabilityOwnerIdentity
                != capabilityOwnerIdentity
            || (pendingRecordingStore.map {
                $0.failedMutationInterlock
                    !== failedHistoryStore.mutationInterlock
            } ?? false)
            || (pendingRecordingStore.map {
                $0.expectedFailedStoreIdentity
                    != failedHistoryStore.storeIdentity
            } ?? false)
            || (pendingRecordingStore.map {
                $0.failedHistoryRetryState.identity
                    != failedHistoryRetryState.identity
            } ?? false)
            || outboxStore.capabilityOwnerIdentity != capabilityOwnerIdentity
            || deliveryStore.capabilityOwnerIdentity
                != capabilityOwnerIdentity
            || outboxStore.deliveryStoreIdentity
                != deliveryStore.storeIdentity
            || deliveryStore.outboxStoreIdentity
                != outboxStore.storeIdentity {
            identityState.markConflicted()
        }
    }

    init(
        policyStore: IOSHistoryPolicyStore,
        acceptedHistoryStore: IOSAcceptedHistoryStore,
        failedHistoryStore: IOSFailedHistoryStore,
        pendingRecordingStore: IOSPendingRecordingStore? = nil,
        outboxStore: IOSAcceptedHistoryOutboxStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        operationGate: IOSPersistenceOperationGate,
        baselineRecoveryState: IOSAcceptedHistoryBaselineRecoveryState =
            IOSAcceptedHistoryBaselineRecoveryState(),
        acceptanceState: IOSAcceptedHistoryAcceptanceOperationState =
            IOSAcceptedHistoryAcceptanceOperationState(),
        pendingReplacementState:
            IOSAcceptedHistoryPendingReplacementOperationState =
                IOSAcceptedHistoryPendingReplacementOperationState(),
        outboxWorkerState:
            IOSAcceptedHistoryOutboxWorkerOperationState =
                IOSAcceptedHistoryOutboxWorkerOperationState(),
        policyCutoverState:
            IOSHistoryPolicyCutoverOperationState =
                IOSHistoryPolicyCutoverOperationState(),
        failedHistoryTransferState:
            IOSFailedHistoryTransferOperationState =
                IOSFailedHistoryTransferOperationState(),
        failedHistoryAudioCleanupState:
            IOSFailedHistoryAudioCleanupOperationState =
                IOSFailedHistoryAudioCleanupOperationState(),
        failedHistoryRetryState:
            IOSFailedHistoryRetryLiveOwnerState? = nil,
        foregroundVoicePersistenceState:
            IOSForegroundVoicePersistenceOperationState =
                IOSForegroundVoicePersistenceOperationState(),
        ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity? = nil,
        repositoryIdentityState:
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState =
                IOSAcceptedHistoryCoordinatorRepositoryIdentityState(),
        repositoryRegistration:
            IOSAcceptedHistoryCoordinatorRepositoryRegistration? = nil
    ) {
        let capabilityOwnerIdentity = ownerIdentity
            ?? policyStore.capabilityOwnerIdentity
        let failedHistoryRetryState = failedHistoryRetryState
            ?? failedHistoryStore.retryLiveOwnerState
        let pendingGateBindingAccepted = pendingRecordingStore?
            .bindOperationGateIdentity(operationGate.identity) ?? true
        let pendingFailedBindingAccepted = pendingRecordingStore.map {
            failedHistoryStore.bindExpectedPendingStoreIdentity(
                $0.storeIdentity
            )
        } ?? true
        let failedGateBindingAccepted =
            failedHistoryStore.bindOperationGateIdentity(
                operationGate.identity
            )
        let failedRetryStateBindingAccepted =
            failedHistoryStore.bindRetryLiveOwnerStateIdentity(
                failedHistoryRetryState.identity
            )
        let failedDeliveryBindingAccepted =
            failedHistoryStore.bindExpectedDeliveryStoreIdentity(
                deliveryStore.storeIdentity
            )
        let outboxGateBindingAccepted =
            outboxStore.bindOperationGateIdentity(operationGate.identity)
        let deliveryGateBindingAccepted =
            deliveryStore.bindOperationGateIdentity(operationGate.identity)
        let deliveryFailedInterlockBindingAccepted =
            deliveryStore.bindFailedHistoryMutationInterlock(
                failedHistoryStore.mutationInterlock
            )
        self.policyStore = policyStore
        self.pendingRecordingStore = pendingRecordingStore
        self.acceptedHistoryStore = acceptedHistoryStore
        self.failedHistoryStore = failedHistoryStore
        self.outboxStore = outboxStore
        self.deliveryStore = deliveryStore
        self.operationGate = operationGate
        self.baselineRecoveryState = baselineRecoveryState
        self.acceptanceState = acceptanceState
        self.pendingReplacementState = pendingReplacementState
        self.outboxWorkerState = outboxWorkerState
        self.policyCutoverState = policyCutoverState
        self.failedHistoryTransferState = failedHistoryTransferState
        self.failedHistoryAudioCleanupState =
            failedHistoryAudioCleanupState
        self.failedHistoryRetryState = failedHistoryRetryState
        self.foregroundVoicePersistenceState =
            foregroundVoicePersistenceState
        self.failedHistoryMutationInterlock =
            failedHistoryStore.mutationInterlock
        self.ownerIdentity = capabilityOwnerIdentity
        self.repositoryIdentityState = repositoryIdentityState
        self.repositoryRegistration = repositoryRegistration
        if !pendingGateBindingAccepted
            || !pendingFailedBindingAccepted
            || !failedGateBindingAccepted
            || !failedRetryStateBindingAccepted
            || !failedDeliveryBindingAccepted
            || !outboxGateBindingAccepted
            || !deliveryGateBindingAccepted
            || !deliveryFailedInterlockBindingAccepted
            || (pendingRecordingStore.map {
                $0.capabilityOwnerIdentity != capabilityOwnerIdentity
            } ?? false)
            || policyStore.capabilityOwnerIdentity != capabilityOwnerIdentity
            || acceptedHistoryStore.capabilityOwnerIdentity
                != capabilityOwnerIdentity
            || failedHistoryStore.capabilityOwnerIdentity
                != capabilityOwnerIdentity
            || (pendingRecordingStore.map {
                $0.failedMutationInterlock
                    !== failedHistoryStore.mutationInterlock
            } ?? false)
            || (pendingRecordingStore.map {
                $0.expectedFailedStoreIdentity
                    != failedHistoryStore.storeIdentity
            } ?? false)
            || (pendingRecordingStore.map {
                $0.failedHistoryRetryState.identity
                    != failedHistoryRetryState.identity
            } ?? false)
            || outboxStore.capabilityOwnerIdentity != capabilityOwnerIdentity
            || deliveryStore.capabilityOwnerIdentity
                != capabilityOwnerIdentity
            || outboxStore.deliveryStoreIdentity
                != deliveryStore.storeIdentity
            || deliveryStore.outboxStoreIdentity
                != outboxStore.storeIdentity {
            repositoryIdentityState.markConflicted()
        }
    }

    public func capture(
        transcriptionModel: String,
        transcriptionLanguageCode: String?,
        durationMilliseconds: Int64?
    ) async throws -> IOSAcceptedOutputHistoryCapture {
        let validatedMarker = try IOSAcceptedOutputHistoryWrite(
            policyGeneration: 1,
            transcriptionModel: transcriptionModel,
            transcriptionLanguageCode: transcriptionLanguageCode,
            durationMilliseconds: durationMilliseconds
        )
        let policyStore = policyStore
        let acceptedHistoryStore = acceptedHistoryStore
        let failedHistoryStore = failedHistoryStore
        let outboxStore = outboxStore
        let deliveryStore = deliveryStore
        let baselineRecoveryState = baselineRecoveryState
        let pendingReplacementState = pendingReplacementState
        let outboxWorkerState = outboxWorkerState
        let policyCutoverState = policyCutoverState
        let failedHistoryTransferState = failedHistoryTransferState
        let failedHistoryRetryState = failedHistoryRetryState
        let foregroundVoicePersistenceState =
            foregroundVoicePersistenceState
        let failedHistoryMutationInterlock =
            failedHistoryMutationInterlock
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration
        let ownerIdentity = ownerIdentity

        do {
            let capture = try await operationGate.perform {
                operationLeaseAuthorization in
                guard await foregroundVoicePersistenceState.current() == nil
                else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                guard await failedHistoryRetryState.hasLiveOwner() == false
                else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                guard !failedHistoryMutationInterlock.isBlocked else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                guard await failedHistoryTransferState.current() == nil else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .localRecoveryPending
                }
                let repositoryBinding = repositoryRegistration?.revalidate()
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                guard await pendingReplacementState.current() == nil else {
                    throw IOSAcceptedOutputDeliveryError.commitUncertain
                }
                guard await outboxWorkerState.current() == nil else {
                    throw IOSAcceptedOutputDeliveryError.commitUncertain
                }
                guard await policyCutoverState.current() == nil else {
                    throw IOSAcceptedOutputDeliveryError.commitUncertain
                }
                do {
                    guard try await failedHistoryStore
                        .hasPendingJournalRetirement(
                            operationLeaseAuthorization:
                                operationLeaseAuthorization
                        ) == false else {
                        throw IOSAcceptedHistoryCoordinatorError
                            .localRecoveryPending
                    }
                    do {
                        let recoveryRequired = await baselineRecoveryState.value()
                        let receipt: IOSHistoryPolicyReceipt
                        if recoveryRequired {
                            receipt = try await Self.establishGuardedBaseline(
                                policyStore: policyStore,
                                acceptedHistoryStore: acceptedHistoryStore,
                                failedHistoryStore: failedHistoryStore,
                                outboxStore: outboxStore,
                                deliveryStore: deliveryStore,
                                isRecovery: true
                            )
                        } else if let current = try await policyStore.load() {
                            receipt = try await policyStore.confirm(
                                expected: IOSHistoryPolicyExpectation(
                                    state: current
                                )
                            )
                        } else {
                            receipt = try await Self.establishGuardedBaseline(
                                policyStore: policyStore,
                                acceptedHistoryStore: acceptedHistoryStore,
                                failedHistoryStore: failedHistoryStore,
                                outboxStore: outboxStore,
                                deliveryStore: deliveryStore,
                                isRecovery: false
                            )
                        }

                        let pendingMarker = try IOSAcceptedOutputHistoryWrite(
                            policyGeneration: receipt.state.policyGeneration,
                            transcriptionModel:
                                validatedMarker.transcriptionModel,
                            transcriptionLanguageCode:
                                validatedMarker.transcriptionLanguageCode,
                            durationMilliseconds:
                                validatedMarker.durationMilliseconds
                        )
                        let capture = IOSAcceptedOutputHistoryCapture(
                            policyReceipt: receipt,
                            ownerIdentity: ownerIdentity,
                            historyWrite: receipt.state.historyEnabled
                                ? pendingMarker
                                : nil
                        )
                        if let repositoryBinding {
                            _ = repositoryRegistration?.revalidate(
                                expectedBinding: repositoryBinding
                            )
                        }
                        guard !repositoryIdentityState.isConflicted else {
                            throw IOSAcceptedHistoryCoordinatorError
                                .repositoryIdentityConflict
                        }
                        await baselineRecoveryState.clear()
                        return capture
                    } catch CaptureOperationError.baselineCommitUncertain {
                        await baselineRecoveryState.requireRecovery()
                        throw IOSHistoryPolicyError.commitUncertain
                    } catch CaptureOperationError.definitiveBaselineConflict {
                        await baselineRecoveryState.clear()
                        throw IOSHistoryPolicyError.compareAndSwapFailed
                    }
                } catch {
                    if let repositoryBinding {
                        _ = repositoryRegistration?.revalidate(
                            expectedBinding: repositoryBinding
                        )
                    }
                    if repositoryIdentityState.isConflicted {
                        throw IOSAcceptedHistoryCoordinatorError
                            .repositoryIdentityConflict
                    }
                    throw error
                }
            }
            return capture
        } catch IOSPersistenceOperationGate.AcquisitionError.cancelledBeforeLease {
            throw IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        } catch IOSPersistenceOperationGate.AcquisitionError.reentrantOperation {
            throw IOSAcceptedHistoryCoordinatorError.reentrantOperation
        }
    }
}

extension IOSAcceptedHistoryCoordinator {
    static func establishGuardedBaseline(
        policyStore: IOSHistoryPolicyStore,
        acceptedHistoryStore: IOSAcceptedHistoryStore,
        failedHistoryStore: IOSFailedHistoryStore,
        outboxStore: IOSAcceptedHistoryOutboxStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        isRecovery: Bool
    ) async throws -> IOSHistoryPolicyReceipt {
        let acceptedHistory = try await acceptedHistoryStore
            .proveGuardedBaseline()
        let failedHistory = try await failedHistoryStore
            .proveGuardedBaseline()
        let outbox = try await outboxStore.proveGuardedBaseline()
        let delivery = try await deliveryStore.proveGuardedBaseline()
        let authorization = try IOSHistoryPolicyBaselineAuthorization(
            acceptedHistory: acceptedHistory,
            outbox: outbox,
            delivery: delivery,
            failedHistory: failedHistory
        )

        do {
            return try await policyStore.establishAndConfirmBaseline(
                authorization: authorization
            )
        } catch IOSHistoryPolicyError.commitUncertain {
            throw CaptureOperationError.baselineCommitUncertain
        } catch IOSHistoryPolicyError.compareAndSwapFailed where isRecovery {
            let current = try await policyStore.load()
            guard let current,
                  current != .baseline else {
                throw IOSHistoryPolicyError.compareAndSwapFailed
            }

            do {
                return try await policyStore.establishAndConfirmBaseline(
                    authorization: authorization
                )
            } catch IOSHistoryPolicyError.commitUncertain {
                throw CaptureOperationError.baselineCommitUncertain
            } catch IOSHistoryPolicyError.compareAndSwapFailed {
                throw CaptureOperationError.definitiveBaselineConflict
            }
        }
    }
}
