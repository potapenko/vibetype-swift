import Foundation
import HoldTypePersistence
import Testing
@testable import HoldTypeIOSCore

struct IOSProviderConsentStageExecutorTests {
    @Test func everyStageLaunchesAndConsumesExactlyOnce() async throws {
        for stage in IOSProviderConsentProviderStage.allCases {
            let gate = ProviderConsentStageGateFake()
            let providerCalls = LockedCounter()

            let outcome: IOSProviderConsentStageOutcome<String, TestFailure> =
                await IOSProviderConsentStageExecutionEngine.execute(
                    gate: gate,
                    authorization: .init(),
                    stage: stage,
                    operation: {
                        providerCalls.increment()
                        return "normalized"
                    },
                    normalizeFailure: { _ in .provider }
                )

            #expect(outcome == .success("normalized"))
            #expect(providerCalls.value == 1)
            #expect(gate.registerCallCount == 1)
            #expect(gate.launchCallCount == 1)
            #expect(gate.finishCallCount == 1)
            #expect(gate.consumeCallCount == 1)
            #expect(gate.consumeOperationCount == 1)
            #expect(gate.registeredStages == [stage])
        }
    }

    @Test func withdrawalBeforeLaunchNeverInvokesProvider() async {
        let gate = ProviderConsentStageGateFake(
            launchBehavior: .withdrawBeforeLaunch
        )
        let providerCalls = LockedCounter()

        let outcome: IOSProviderConsentStageOutcome<Int, TestFailure> =
            await IOSProviderConsentStageExecutionEngine.execute(
                gate: gate,
                authorization: .init(),
                stage: .transcription,
                operation: {
                    providerCalls.increment()
                    return 1
                },
                normalizeFailure: { _ in .provider }
            )

        #expect(outcome == .authorizationUnavailable)
        #expect(providerCalls.value == 0)
        #expect(gate.launchPermitCallCount == 0)
        #expect(gate.finishCallCount == 0)
        #expect(gate.consumeCallCount == 0)
    }

    @Test func withdrawalDuringResultRejectsNormalizedPayload() async {
        let gate = ProviderConsentStageGateFake(
            resultBehavior: .withdrawBeforeConsume
        )

        let outcome: IOSProviderConsentStageOutcome<String, TestFailure> =
            await IOSProviderConsentStageExecutionEngine.execute(
                gate: gate,
                authorization: .init(),
                stage: .correction,
                operation: { "normalized correction" },
                normalizeFailure: { _ in .provider }
            )

        #expect(outcome == .authorizationUnavailable)
        #expect(gate.finishCallCount == 1)
        #expect(gate.resultCancellationCount == 1)
        #expect(gate.consumeCallCount == 1)
        #expect(gate.consumeOperationCount == 0)
    }

    @Test func withdrawalCompletesBeforeNoncooperativeLateResult() async {
        let gate = ProviderConsentStageGateFake()
        let provider = ControlledProviderOperation(value: "late transcript")
        let outcome = LockedBox<
            IOSProviderConsentStageOutcome<String, TestFailure>?
        >(nil)
        let executionFinished = TestSignal()
        let execution = Task {
            let value: IOSProviderConsentStageOutcome<String, TestFailure> =
                await IOSProviderConsentStageExecutionEngine.execute(
                    gate: gate,
                    authorization: ProviderConsentStageAuthorization(),
                    stage: .transcription,
                    operation: { await provider.execute() },
                    normalizeFailure: { _ in .provider }
                )
            outcome.set(value)
            executionFinished.signal()
        }
        await provider.waitUntilStarted()

        gate.withdrawAllAuthorizations()

        #expect(executionFinished.wait(timeout: 1))
        #expect(outcome.value == .authorizationUnavailable)
        #expect(gate.finishCallCount == 0)
        #expect(gate.consumeCallCount == 0)

        await provider.release()
        await execution.value
        #expect(gate.finishCallCount == 0)
        #expect(gate.consumeCallCount == 0)
    }

    @Test func callerCancellationIsBoundedAndCancelsRegistration() async {
        let gate = ProviderConsentStageGateFake()
        let provider = ControlledProviderOperation(value: 7)
        let outcome = LockedBox<
            IOSProviderConsentStageOutcome<Int, TestFailure>?
        >(nil)
        let executionFinished = TestSignal()
        let execution = Task {
            let value: IOSProviderConsentStageOutcome<Int, TestFailure> =
                await IOSProviderConsentStageExecutionEngine.execute(
                    gate: gate,
                    authorization: ProviderConsentStageAuthorization(),
                    stage: .translation,
                    operation: { await provider.execute() },
                    normalizeFailure: { _ in .provider }
                )
            outcome.set(value)
            executionFinished.signal()
        }
        await provider.waitUntilStarted()

        execution.cancel()

        #expect(executionFinished.wait(timeout: 1))
        #expect(outcome.value == .cancelled)
        #expect(gate.cancelDispatchCallCount >= 1)
        #expect(gate.finishCallCount == 0)

        await provider.release()
        await execution.value
    }

    @Test func thrownProviderErrorIsNormalizedBeforeConsumption() async {
        let gate = ProviderConsentStageGateFake()
        let normalizedFailures = LockedCounter()
        let canary = "RAW-PROVIDER-ERROR-CANARY"

        let outcome: IOSProviderConsentStageOutcome<Int, TestFailure> =
            await IOSProviderConsentStageExecutionEngine.execute(
                gate: gate,
                authorization: .init(),
                stage: .translation,
                operation: {
                    throw CanaryProviderError(payload: canary)
                },
                normalizeFailure: { _ in
                    normalizedFailures.increment()
                    return .provider
                }
            )

        #expect(outcome == .failure(.provider))
        #expect(normalizedFailures.value == 1)
        #expect(gate.consumeOperationCount == 1)
        expectRedacted(outcome, excluding: canary)
    }

    @Test func asynchronousPersistenceStartsOnlyAfterConsentConsumption()
        async {
        let gate = ProviderConsentStageGateFake()
        let persistence = AsyncPersistenceProbe(gate: gate)

        let outcome: IOSProviderConsentStageOutcome<String, TestFailure> =
            await IOSProviderConsentStageExecutionEngine.execute(
                gate: gate,
                authorization: .init(),
                stage: .transcription,
                operation: { "accepted transcript" },
                normalizeFailure: { _ in .provider }
            )
        await persistence.persist(outcome)

        #expect(outcome == .success("accepted transcript"))
        #expect(gate.consumeOperationCount == 1)
        #expect(await persistence.didRun)
        #expect(await persistence.observedOutsideConsentFence)
    }

    @Test func outcomeDescriptionsAndReflectionAreRedacted() {
        let canary = "NORMALIZED-STAGE-PAYLOAD-CANARY"
        let success = IOSProviderConsentStageOutcome<String, String>
            .success(canary)
        let failure = IOSProviderConsentStageOutcome<String, String>
            .failure(canary)
        let controls: [IOSProviderConsentStageOutcome<String, String>] = [
            .cancelled,
            .authorizationUnavailable,
        ]

        expectRedacted(success, excluding: canary)
        expectRedacted(failure, excluding: canary)
        controls.forEach { expectRedacted($0, excluding: canary) }
    }
}

private enum TestFailure: Equatable, Sendable {
    case provider
}

private struct CanaryProviderError: Error, Sendable {
    let payload: String
}

private struct ProviderConsentStageAuthorization: Equatable, Sendable {
    private let identifier = UUID()
}

private struct ProviderConsentStageRegistration: Equatable, Sendable {
    private let identifier = UUID()
}

private struct ProviderConsentStageResultAuthorization: Equatable, Sendable {
    private let identifier = UUID()
}

private final class ProviderConsentStageGateFake:
    IOSProviderConsentStageGating,
    @unchecked Sendable {
    enum LaunchBehavior {
        case launch
        case withdrawBeforeLaunch
    }

    enum ResultBehavior {
        case consume
        case withdrawBeforeConsume
    }

    private struct DispatchState {
        let registration: ProviderConsentStageRegistration
        let onCancellation: @Sendable () -> Void
        var didLaunch = false
    }

    private struct ResultState {
        let authorization: ProviderConsentStageResultAuthorization
        let onCancellation: @Sendable () -> Void
    }

    private let lock = NSLock()
    private let launchBehavior: LaunchBehavior
    private let resultBehavior: ResultBehavior
    private var dispatchState: DispatchState?
    private var resultState: ResultState?
    private var storedRegisterCallCount = 0
    private var storedLaunchCallCount = 0
    private var storedLaunchPermitCallCount = 0
    private var storedCancelDispatchCallCount = 0
    private var storedFinishCallCount = 0
    private var storedConsumeCallCount = 0
    private var storedConsumeOperationCount = 0
    private var storedResultCancellationCount = 0
    private var storedRegisteredStages: [IOSProviderConsentProviderStage] = []
    private var consuming = false

    init(
        launchBehavior: LaunchBehavior = .launch,
        resultBehavior: ResultBehavior = .consume
    ) {
        self.launchBehavior = launchBehavior
        self.resultBehavior = resultBehavior
    }

    var registerCallCount: Int {
        lock.withLock { storedRegisterCallCount }
    }
    var launchCallCount: Int { lock.withLock { storedLaunchCallCount } }
    var launchPermitCallCount: Int {
        lock.withLock { storedLaunchPermitCallCount }
    }
    var cancelDispatchCallCount: Int {
        lock.withLock { storedCancelDispatchCallCount }
    }
    var finishCallCount: Int { lock.withLock { storedFinishCallCount } }
    var consumeCallCount: Int { lock.withLock { storedConsumeCallCount } }
    var consumeOperationCount: Int {
        lock.withLock { storedConsumeOperationCount }
    }
    var resultCancellationCount: Int {
        lock.withLock { storedResultCancellationCount }
    }
    var registeredStages: [IOSProviderConsentProviderStage] {
        lock.withLock { storedRegisteredStages }
    }
    var isConsuming: Bool { lock.withLock { consuming } }

    func registerProviderDispatch(
        _ authorization: ProviderConsentStageAuthorization,
        for stage: IOSProviderConsentProviderStage,
        onCancellation: @escaping @Sendable () -> Void
    ) async -> ProviderConsentStageRegistration? {
        _ = authorization
        return lock.withLock {
            storedRegisterCallCount += 1
            storedRegisteredStages.append(stage)
            guard dispatchState == nil, resultState == nil else {
                return nil
            }
            let registration = ProviderConsentStageRegistration()
            dispatchState = DispatchState(
                registration: registration,
                onCancellation: onCancellation
            )
            return registration
        }
    }

    func launchProviderDispatch(
        _ registration: ProviderConsentStageRegistration,
        launch: @Sendable () -> Void
    ) async -> Bool {
        var cancellation: (@Sendable () -> Void)?
        let shouldLaunch = lock.withLock {
            storedLaunchCallCount += 1
            guard var state = dispatchState,
                  state.registration == registration else {
                return false
            }
            switch launchBehavior {
            case .launch:
                state.didLaunch = true
                dispatchState = state
                return true
            case .withdrawBeforeLaunch:
                cancellation = state.onCancellation
                dispatchState = nil
                return false
            }
        }
        cancellation?()
        guard shouldLaunch else { return false }
        lock.withLock { storedLaunchPermitCallCount += 1 }
        launch()
        return true
    }

    func cancelProviderDispatch(
        _ registration: ProviderConsentStageRegistration
    ) {
        let cancellation = lock.withLock { ()
            -> (@Sendable () -> Void)? in
            storedCancelDispatchCallCount += 1
            guard let state = dispatchState,
                  state.registration == registration else {
                return nil
            }
            dispatchState = nil
            return state.onCancellation
        }
        cancellation?()
    }

    func finishProviderDispatch(
        _ registration: ProviderConsentStageRegistration,
        onResultCancellation: @escaping @Sendable () -> Void
    ) async -> ProviderConsentStageResultAuthorization? {
        lock.withLock {
            storedFinishCallCount += 1
            guard let state = dispatchState,
                  state.registration == registration,
                  state.didLaunch else {
                return nil
            }
            dispatchState = nil
            let authorization = ProviderConsentStageResultAuthorization()
            resultState = ResultState(
                authorization: authorization,
                onCancellation: onResultCancellation
            )
            return authorization
        }
    }

    func consumeProviderResult<Value: Sendable>(
        _ authorization: ProviderConsentStageResultAuthorization,
        perform operation: @Sendable () throws -> Value
    ) async rethrows -> Value? {
        var cancellation: (@Sendable () -> Void)?
        let canConsume = lock.withLock {
            storedConsumeCallCount += 1
            guard let state = resultState,
                  state.authorization == authorization else {
                return false
            }
            if resultBehavior == .withdrawBeforeConsume {
                storedResultCancellationCount += 1
                cancellation = state.onCancellation
                resultState = nil
                return false
            }
            consuming = true
            return true
        }
        cancellation?()
        guard canConsume else { return nil }

        do {
            let value = try operation()
            lock.withLock {
                storedConsumeOperationCount += 1
                consuming = false
                if resultState?.authorization == authorization {
                    resultState = nil
                }
            }
            return value
        } catch {
            lock.withLock { consuming = false }
            throw error
        }
    }

    func abandonProviderResult(
        _ authorization: ProviderConsentStageResultAuthorization
    ) {
        let cancellation = lock.withLock { ()
            -> (@Sendable () -> Void)? in
            guard let state = resultState,
                  state.authorization == authorization else {
                return nil
            }
            resultState = nil
            return state.onCancellation
        }
        cancellation?()
    }

    func withdrawAllAuthorizations() {
        let cancellations = lock.withLock {
            let values = [
                dispatchState?.onCancellation,
                resultState?.onCancellation,
            ].compactMap { $0 }
            dispatchState = nil
            resultState = nil
            return values
        }
        cancellations.forEach { $0() }
    }
}

private actor ControlledProviderOperation<Value: Sendable> {
    private let value: Value
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<Value, Never>?

    init(value: Value) {
        self.value = value
    }

    func execute() async -> Value {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll(keepingCapacity: false)
        return await withCheckedContinuation { continuation in
            precondition(completion == nil)
            completion = continuation
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        let continuation = completion
        completion = nil
        continuation?.resume(returning: value)
    }
}

private actor AsyncPersistenceProbe {
    private let gate: ProviderConsentStageGateFake
    private(set) var didRun = false
    private(set) var observedOutsideConsentFence = false

    init(gate: ProviderConsentStageGateFake) {
        self.gate = gate
    }

    func persist<Success: Sendable, Failure: Sendable>(
        _ outcome: IOSProviderConsentStageOutcome<Success, Failure>
    ) async {
        _ = outcome
        await Task.yield()
        didRun = true
        observedOutsideConsentFence = !gate.isConsuming
    }
}

private final class TestSignal: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func signal() {
        semaphore.signal()
    }

    func wait(timeout: TimeInterval) -> Bool {
        semaphore.wait(timeout: .now() + timeout) == .success
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int { lock.withLock { storedValue } }

    func increment() {
        lock.withLock { storedValue += 1 }
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value { lock.withLock { storedValue } }

    func set(_ value: Value) {
        lock.withLock { storedValue = value }
    }
}

private func expectRedacted<Value>(_ value: Value, excluding canary: String) {
    var dumped = ""
    dump(value, to: &dumped)
    #expect(!String(describing: value).contains(canary))
    #expect(!String(reflecting: value).contains(canary))
    #expect(!dumped.contains(canary))
    #expect(dumped.filter { $0 == "\n" }.count <= 1)
}
