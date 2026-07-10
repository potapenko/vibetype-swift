import Darwin
import Foundation

/// Sealed proof that the containing-app coordinator observed every legacy
/// History owner as absent or empty before creating the physical 1/1 policy.
struct IOSHistoryPolicyBaselineAuthorization: Sendable {
    fileprivate init(
        acceptedHistory: IOSAcceptedHistoryGuardedBaselineEvidence,
        outbox: IOSAcceptedHistoryOutboxGuardedBaselineEvidence,
        delivery: IOSAcceptedOutputDeliveryGuardedBaselineEvidence
    ) {
        _ = acceptedHistory
        _ = outbox
        _ = delivery
    }

    init(testingToken: Void) {}
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
    let policyStore: IOSHistoryPolicyStore
    let acceptedHistoryStore: IOSAcceptedHistoryStore
    let outboxStore: IOSAcceptedHistoryOutboxStore
    let deliveryStore: IOSAcceptedOutputDeliveryStore
    let baselineRecoveryState: IOSAcceptedHistoryBaselineRecoveryState
    let repositoryIdentityState:
        IOSAcceptedHistoryCoordinatorRepositoryIdentityState

    init(applicationSupportDirectoryURL: URL) {
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
        policyStore = IOSHistoryPolicyStore(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        acceptedHistoryStore = IOSAcceptedHistoryStore(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        outboxStore = IOSAcceptedHistoryOutboxStore(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        deliveryStore = IOSAcceptedOutputDeliveryStore(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        baselineRecoveryState = IOSAcceptedHistoryBaselineRecoveryState()
        repositoryIdentityState =
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState()
    }
}

struct IOSAcceptedHistoryCoordinatorRepositoryBinding: Equatable, Sendable {
    fileprivate let resolvedPath: String
    fileprivate let device: dev_t?
    fileprivate let inode: ino_t?
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
    private struct PhysicalRootKey: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    private struct RootResolution {
        let lexicalKeys: [String]
        let resolvedRoot: URL
        let physicalKey: PhysicalRootKey?

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
    }

    private let lock = NSLock()
    private var contextsByLexicalRoot:
        [String: IOSAcceptedHistoryCoordinatorProcessContext] = [:]
    private var contextsByPhysicalRoot:
        [PhysicalRootKey: IOSAcceptedHistoryCoordinatorProcessContext] = [:]
    private var conflictedPhysicalRoots: Set<PhysicalRootKey> = []
    private var registeredInputRoots: [RegisteredInputRoot] = []

    func context(
        for applicationSupportDirectoryURL: URL
    ) -> IOSAcceptedHistoryCoordinatorProcessContext {
        return lock.withLock {
            let resolution = rootResolution(
                for: applicationSupportDirectoryURL
            )
            let candidates = contextCandidates(for: resolution)
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
                applicationSupportDirectoryURL: resolution.resolvedRoot
            )
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
        if currentRoot.path == resolution.resolvedRoot.path {
            return true
        }
        guard let physicalKey = resolution.physicalKey else { return false }
        return physicalRootKey(for: currentRoot) == physicalKey
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
            physicalKey: physicalRootKey(for: resolvedRoot)
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
            RegisteredInputRoot(url: url, context: context)
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
                registration.context.repositoryIdentityState.markConflicted()
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
            expectedBinding: expectedBinding
        )
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
    fileprivate let policyReceipt: IOSHistoryPolicyReceipt
    let historyWrite: IOSAcceptedOutputHistoryWrite?

    fileprivate init(
        policyReceipt: IOSHistoryPolicyReceipt,
        historyWrite: IOSAcceptedOutputHistoryWrite?
    ) {
        self.policyReceipt = policyReceipt
        self.historyWrite = historyWrite
    }

    init(
        testingPolicyReceipt policyReceipt: IOSHistoryPolicyReceipt,
        historyWrite: IOSAcceptedOutputHistoryWrite?
    ) {
        self.init(
            policyReceipt: policyReceipt,
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
    private enum CaptureOperationError: Error, Sendable {
        case baselineCommitUncertain
        case definitiveBaselineConflict
    }

    private static let processOperationGate = IOSPersistenceOperationGate()
    private static let processContextRegistry =
        IOSAcceptedHistoryCoordinatorProcessContextRegistry()

    private let policyStore: IOSHistoryPolicyStore
    private let acceptedHistoryStore: IOSAcceptedHistoryStore
    private let outboxStore: IOSAcceptedHistoryOutboxStore
    private let deliveryStore: IOSAcceptedOutputDeliveryStore
    private let operationGate: IOSPersistenceOperationGate
    private let baselineRecoveryState: IOSAcceptedHistoryBaselineRecoveryState
    private let repositoryIdentityState:
        IOSAcceptedHistoryCoordinatorRepositoryIdentityState
    private let repositoryRegistration:
        IOSAcceptedHistoryCoordinatorRepositoryRegistration?

    public init(applicationSupportDirectoryURL: URL) {
        let context = Self.processContextRegistry.context(
            for: applicationSupportDirectoryURL
        )
        policyStore = context.policyStore
        acceptedHistoryStore = context.acceptedHistoryStore
        outboxStore = context.outboxStore
        deliveryStore = context.deliveryStore
        operationGate = Self.processOperationGate
        baselineRecoveryState = context.baselineRecoveryState
        repositoryIdentityState = context.repositoryIdentityState
        repositoryRegistration =
            IOSAcceptedHistoryCoordinatorRepositoryRegistration(
                registry: Self.processContextRegistry,
                context: context,
                applicationSupportDirectoryURL:
                    applicationSupportDirectoryURL
            )
    }

    init(
        policyStore: IOSHistoryPolicyStore,
        acceptedHistoryStore: IOSAcceptedHistoryStore,
        outboxStore: IOSAcceptedHistoryOutboxStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore
    ) {
        self.policyStore = policyStore
        self.acceptedHistoryStore = acceptedHistoryStore
        self.outboxStore = outboxStore
        self.deliveryStore = deliveryStore
        operationGate = Self.processOperationGate
        baselineRecoveryState = IOSAcceptedHistoryBaselineRecoveryState()
        repositoryIdentityState =
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState()
        repositoryRegistration = nil
    }

    init(
        policyStore: IOSHistoryPolicyStore,
        acceptedHistoryStore: IOSAcceptedHistoryStore,
        outboxStore: IOSAcceptedHistoryOutboxStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        operationGate: IOSPersistenceOperationGate,
        baselineRecoveryState: IOSAcceptedHistoryBaselineRecoveryState =
            IOSAcceptedHistoryBaselineRecoveryState(),
        repositoryIdentityState:
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState =
                IOSAcceptedHistoryCoordinatorRepositoryIdentityState(),
        repositoryRegistration:
            IOSAcceptedHistoryCoordinatorRepositoryRegistration? = nil
    ) {
        self.policyStore = policyStore
        self.acceptedHistoryStore = acceptedHistoryStore
        self.outboxStore = outboxStore
        self.deliveryStore = deliveryStore
        self.operationGate = operationGate
        self.baselineRecoveryState = baselineRecoveryState
        self.repositoryIdentityState = repositoryIdentityState
        self.repositoryRegistration = repositoryRegistration
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
        let outboxStore = outboxStore
        let deliveryStore = deliveryStore
        let baselineRecoveryState = baselineRecoveryState
        let repositoryIdentityState = repositoryIdentityState
        let repositoryRegistration = repositoryRegistration

        do {
            let capture = try await operationGate.perform {
                let repositoryBinding = repositoryRegistration?.revalidate()
                guard !repositoryIdentityState.isConflicted else {
                    throw IOSAcceptedHistoryCoordinatorError
                        .repositoryIdentityConflict
                }
                do {
                    do {
                        let recoveryRequired = await baselineRecoveryState.value()
                        let receipt: IOSHistoryPolicyReceipt
                        if recoveryRequired {
                            receipt = try await Self.establishGuardedBaseline(
                                policyStore: policyStore,
                                acceptedHistoryStore: acceptedHistoryStore,
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

private extension IOSAcceptedHistoryCoordinator {
    static func establishGuardedBaseline(
        policyStore: IOSHistoryPolicyStore,
        acceptedHistoryStore: IOSAcceptedHistoryStore,
        outboxStore: IOSAcceptedHistoryOutboxStore,
        deliveryStore: IOSAcceptedOutputDeliveryStore,
        isRecovery: Bool
    ) async throws -> IOSHistoryPolicyReceipt {
        let acceptedHistory = try await acceptedHistoryStore
            .proveGuardedBaseline()
        let outbox = try await outboxStore.proveGuardedBaseline()
        let delivery = try await deliveryStore.proveGuardedBaseline()
        let authorization = IOSHistoryPolicyBaselineAuthorization(
            acceptedHistory: acceptedHistory,
            outbox: outbox,
            delivery: delivery
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
