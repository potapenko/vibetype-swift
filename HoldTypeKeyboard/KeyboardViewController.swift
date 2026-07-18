import OSLog
import UIKit

/// Reads UIKit's document identity without trusting its nonnull annotation.
///
/// A freshly recreated keyboard can temporarily receive `nil` from its
/// Objective-C document proxy even though the SDK imports this property as a
/// nonoptional Swift `UUID`. Accessing the imported property in that window
/// traps inside Foundation's UUID bridge.
@MainActor
enum KeyboardDocumentIdentifierAdapter {
    private static let selector = NSSelectorFromString("documentIdentifier")

    static func load(from documentProxy: any UITextDocumentProxy) -> UUID? {
        load(fromObjectiveCObject: documentProxy as AnyObject)
    }

    static func load(fromObjectiveCObject object: AnyObject) -> UUID? {
        guard let object = object as? NSObject,
              object.responds(to: selector),
              let unmanagedIdentifier = object.perform(selector),
              let identifier = unmanagedIdentifier.takeUnretainedValue()
                as? NSUUID else {
            return nil
        }
        return identifier as UUID
    }
}

/// Opens the containing app from the keyboard's explicit user gesture.
///
/// `NSExtensionContext.open` is not dispatched for the keyboard extension
/// point on the current signed device. The approved Flow-style behavior
/// therefore routes the same URL through the active responder chain first and
/// keeps the extension-context API as a fallback.
@MainActor
enum KeyboardContainingAppLaunchAdapter {
    private typealias OpenURLCompletionHandler = @convention(block) (Bool) -> Void
    private typealias OpenURLMethod = @convention(c) (
        AnyObject,
        Selector,
        NSURL,
        NSDictionary,
        OpenURLCompletionHandler?
    ) -> Void

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier
            ?? "app.holdtype.HoldType.ios.keyboard",
        category: "handoff"
    )

    static func open(
        _ url: URL,
        from rootResponder: UIResponder,
        extensionContext: NSExtensionContext?,
        completion: @escaping (Bool) -> Void
    ) {
        logger.info("launch requested")
        if openThroughResponderChain(
            url,
            from: rootResponder,
            completion: { didOpen in
                if didOpen {
                    logger.info("responder launch succeeded")
                    completion(true)
                } else {
                    logger.error("responder launch failed")
                    openThroughExtensionContext(
                        url,
                        extensionContext: extensionContext,
                        completion: completion
                    )
                }
            }
        ) {
            return
        }
        openThroughExtensionContext(
            url,
            extensionContext: extensionContext,
            completion: completion
        )
    }

    private static func openThroughExtensionContext(
        _ url: URL,
        extensionContext: NSExtensionContext?,
        completion: @escaping (Bool) -> Void
    ) {
        guard let extensionContext else {
            logger.error("launch unavailable")
            completion(false)
            return
        }
        extensionContext.open(url) { didOpen in
            if didOpen {
                logger.info("extension-context launch succeeded")
            } else {
                logger.error("extension-context launch failed")
            }
            completion(didOpen)
        }
    }

    static func openThroughResponderChain(
        _ url: URL,
        from rootResponder: UIResponder,
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        let selector = NSSelectorFromString(
            "openURL:options:completionHandler:"
        )
        var responder: UIResponder? = rootResponder
        var applicationResponder: UIResponder?
        while let current = responder {
            if current.responds(to: selector) {
                // UIScene exposes the same selector with a different options
                // object. UIApplication is the terminal matching responder.
                applicationResponder = current
            }
            responder = current.next
        }
        guard let applicationResponder else {
            return false
        }
        let implementation = applicationResponder.method(for: selector)
        let openURL = unsafeBitCast(
            implementation,
            to: OpenURLMethod.self
        )
        let completionHandler: OpenURLCompletionHandler = {
            didOpen in
            completion(didOpen)
        }
        openURL(
            applicationResponder,
            selector,
            url as NSURL,
            NSDictionary(),
            completionHandler
        )
        return true
    }
}

final class KeyboardViewController: UIInputViewController {
    private static let maximumDocumentIdentifierRetryCount = 20
    /// Listening state includes two seconds for recorder finalization after
    /// the user-visible five-minute capture boundary.
    private static let listeningFinalizationGrace: TimeInterval = 2
    private static let deliveryLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier
            ?? "app.holdtype.HoldType.ios.keyboard",
        category: "delivery"
    )

    let keyboardView = BrandStageKeyboardView()
    private let deleteRepeater = KeyboardDeleteRepeater()
    private var dependencies = KeyboardViewControllerDependencies.live
    private var lastDiagnosticState: IOSDiagnosticKeyboardState?
    private var cursorAccumulator = KeyboardCursorDragAccumulator()
    private var previousCursorLocationX: CGFloat?
    private var insertionGate = KeyboardInsertionEventGate()
    private var latestItem: KeyboardBridgeItem?
    private var dictationExpiryTimer: Timer?
    private var listeningCountdownTimer: Timer?
    private var documentIdentifierRetryTimer: Timer?
    private var documentIdentifierRetryRequestID: UUID?
    private var documentIdentifierRetryCount = 0
    private var documentIdentifierRetryIsScheduled = false
    private var deliveryObservationTimer: Timer?
    private var pendingDeliveryObservation: (
        requestID: UUID,
        claimID: UUID
    )?
    private var dictationObserver: KeyboardDictationBridgeObserver?
    private var dictationState: KeyboardDictationStateRecord?
    private var activeDictationOwnership:
        KeyboardDictationAttemptIdentity?
    private var expiredAttemptReconnect:
        ExpiredAttemptReconnect?
    private var retiredDictationAttempt:
        KeyboardDictationAttemptIdentity?
    private var authoritativeIdleReadyPublishedAt: Date?
    private let controllerLifetimeID = UUID()
    private var acceptsAutomaticDelivery = false
    private var automaticDeliveryRequestID: UUID?
    private var automaticDeliveryDisqualifiedRequestID: UUID?
    private var recoverableDictationResult: (requestID: UUID, text: String)?
    private var insertedDictationRequestID: UUID?
    private var pendingDeliveryClaimID: UUID?
    private var pendingExplicitDeliveryRequestID: UUID?
    private var lastSeenDictationSessionID: UUID?
    private var pendingDictationCommand: KeyboardDictationCommandKind?
    private var pendingHandoffRequestID: UUID?
    private var handoffLaunchFailed = false
    private var forcesSessionNotRunning = false
    private var showsInputModeSwitchKey = true
    private var allowsStateReconnection = true
    private var automaticVoiceAction: KeyboardVoiceAction = .standard

    private struct ExpiredAttemptReconnect {
        let identity: KeyboardDictationAttemptIdentity
        let publishedAt: Date
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        hasDictationKey = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        hasDictationKey = true
    }

    convenience init(dependencies: KeyboardViewControllerDependencies) {
        self.init(nibName: nil, bundle: nil)
        self.dependencies = dependencies
    }

    private var activeDocumentProxy: any UITextDocumentProxy {
        if let documentProxyProviderOverride =
            dependencies.documentProxyProviderOverride {
            return documentProxyProviderOverride()
        }
        return dependencies.documentProxyOverride ?? textDocumentProxy
    }

    private var activeDocumentIdentifier: UUID? {
        dependencies.loadDocumentIdentifier(activeDocumentProxy)
    }

    private var shouldShowInputModeSwitchKey: Bool {
        dependencies.inputModeSwitchKeyOverride
            ?? needsInputModeSwitchKey
    }

    private var hasSharedContainerAccess: Bool {
        dependencies.fullAccessOverride ?? hasFullAccess
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        showsInputModeSwitchKey = shouldShowInputModeSwitchKey
        configureKeyboardView()
        reloadSharedSnapshot()
        dictationObserver = dependencies.observeDictationState {
            [weak self] in
            self?.reloadDictationState()
        }
        reloadDictationState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasDictationKey = true
        recordKeyboardState(.opened)
        beginExtensionLifetime()
        showsInputModeSwitchKey = shouldShowInputModeSwitchKey
        reloadSharedSnapshot()
        reloadDictationState()
        refreshAutomaticDeliveryEligibility()
        render()
    }

    override func viewWillDisappear(_ animated: Bool) {
        recordKeyboardState(.closed)
        deleteRepeater.stop()
        dictationExpiryTimer?.invalidate()
        dictationExpiryTimer = nil
        cancelListeningCountdown()
        cancelDocumentIdentifierRetry()
        cancelDeliveryObservation()
        endExtensionLifetime()
        super.viewWillDisappear(animated)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        keyboardView.updatePreferredHeight(for: traitCollection)
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        if let observation = pendingDeliveryObservation {
            let currentDocumentID = activeDocumentIdentifier
            recordDelivery(
                .textWillChange,
                requestID: observation.requestID,
                claimID: observation.claimID,
                sourceDocumentID: activeDictationOwnership?.sourceDocumentID,
                currentDocumentID: currentDocumentID
            )
        }
        refreshAutomaticDeliveryEligibility()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if let observation = pendingDeliveryObservation {
            let currentDocumentID = activeDocumentIdentifier
            recordDelivery(
                .textDidChange,
                requestID: observation.requestID,
                claimID: observation.claimID,
                sourceDocumentID: activeDictationOwnership?.sourceDocumentID,
                currentDocumentID: currentDocumentID
            )
            cancelDeliveryObservation()
        }
        refreshAutomaticDeliveryEligibility()
        showsInputModeSwitchKey = shouldShowInputModeSwitchKey
        reloadSharedSnapshot()
        reloadDictationState()
    }

    private func configureKeyboardView() {
        view.backgroundColor = .clear
        view.addSubview(keyboardView)
        NSLayoutConstraint.activate([
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        keyboardView.nextKeyboardButton.addTarget(
            self,
            action: #selector(handleInputModeList(from:with:)),
            for: .allTouchEvents
        )
        keyboardView.onHistoryRequested = { [weak self] in
            self?.openHistory()
        }
        keyboardView.onLatestRequested = { [weak self] in
            self?.insertLatestOrRecoverableResult()
        }
        keyboardView.onMicrophoneRequested = { [weak self] in
            self?.handleMicrophoneCommand()
        }
        keyboardView.onQuickInsertRequested = { [weak self] text in
            self?.insertText(text)
        }
        keyboardView.onAutomaticVoiceActionChanged = { [weak self] action in
            self?.selectAutomaticVoiceAction(action)
        }
        keyboardView.onSpaceRequested = { [weak self] in
            self?.insertText(" ")
        }
        keyboardView.onSpaceCursorGesture = { [weak self] state, x in
            self?.handleCursorGesture(state: state, locationX: x)
        }
        keyboardView.onCursorStepRequested = { [weak self] offset in
            self?.activeDocumentProxy.adjustTextPosition(
                byCharacterOffset: offset
            )
        }
        keyboardView.onDeleteStarted = { [weak self] in
            guard let self else { return }
            deleteRepeater.start { [weak self] in
                self?.activeDocumentProxy.deleteBackward()
            }
        }
        keyboardView.onDeleteStopped = { [weak self] in
            self?.deleteRepeater.stop()
        }
        keyboardView.onReturnRequested = { [weak self] in
            self?.insertText("\n")
        }
    }

    private func reloadSharedSnapshot() {
        do {
            guard let snapshot = try dependencies.loadSnapshot() else {
                setLatestItem(nil)
                render()
                return
            }

            setLatestItem(snapshot.latestForInsertion())
        } catch {
            setLatestItem(nil)
        }
        render()
    }

    private func render() {
        let dictationPresentation = currentDictationPresentation
        keyboardView.render(
            BrandStageKeyboardPresentation(
                status: dictationPresentation.status,
                voiceStage: dictationPresentation.voiceStage,
                listeningCountdownSeconds: listeningCountdownSeconds(
                    for: dictationPresentation.voiceStage
                ),
                automaticVoiceAction: automaticVoiceAction,
                latestIsEnabled: recoverableDictationResult != nil
                    || latestItem != nil,
                returnKey: KeyboardReturnKeyPresentation(
                    semantic: Self.returnSemantic(
                        for: activeDocumentProxy.returnKeyType ?? .default
                    )
                ),
                returnIsEnabled: returnIsEnabled,
                showsInputModeSwitchKey: showsInputModeSwitchKey
            )
        )
    }

    private func listeningCountdownSeconds(
        for voiceStage: KeyboardVoiceStagePresentation
    ) -> Int? {
        guard voiceStage == .listening,
              let dictationState,
              dictationState.phase == .listening,
              owns(dictationState) else {
            return nil
        }

        let captureRemaining = dictationState.expiresAt.timeIntervalSince(
            dependencies.now()
        ) - Self.listeningFinalizationGrace
        let wholeSeconds = Int(ceil(captureRemaining))
        guard (1...60).contains(wholeSeconds) else { return nil }
        return wholeSeconds
    }

    private var currentDictationPresentation: (
        status: KeyboardVoiceStatus,
        voiceStage: KeyboardVoiceStagePresentation
    ) {
        guard hasSharedContainerAccess else {
            recordKeyboardState(.noSharedAccess)
            return (
                .fullAccessRequired,
                .ready
            )
        }
        if pendingHandoffRequestID != nil {
            return (
                .openingHoldType,
                .opening
            )
        }
        guard !forcesSessionNotRunning, let dictationState else {
            return (
                handoffLaunchFailed ? .launchFailed : .ready,
                .ready
            )
        }
        if pendingDictationCommand == .start,
           owns(dictationState) {
            return (.starting, .starting)
        }
        if pendingDictationCommand == .finish,
           owns(dictationState) {
            return (.processing, .processing)
        }
        switch dictationState.phase {
        case .ready:
            if dictationState.hasActiveAttempt, owns(dictationState) {
                return (.openingHoldType, .opening)
            }
            return (.ready, .ready)
        case .listening
            where !owns(dictationState):
            return (
                .ready,
                .ready
            )
        case .listening:
            return (.listening, .listening)
        case .processing
            where !owns(dictationState):
            return (
                .ready,
                .ready
            )
        case .processing:
            return (.processing, .processing)
        case .resultReady, .unavailable:
            return (
                .ready,
                .ready
            )
        case .failed:
            return (
                .dictationFailed,
                .ready
            )
        }
    }

    private func reloadDictationState() {
        dictationExpiryTimer?.invalidate()
        dictationExpiryTimer = nil
        cancelListeningCountdown()
        guard hasSharedContainerAccess else {
            dictationState = nil
            activeDictationOwnership = nil
            recoverableDictationResult = nil
            pendingDictationCommand = nil
            render()
            return
        }
        do {
            guard let state = try dependencies.loadDictationState(),
                  state.isValid(at: dependencies.now()) else {
                recordKeyboardState(.expired)
                preserveExpiredAttemptReconnect()
                cancelDocumentIdentifierRetry()
                dictationState = nil
                activeDictationOwnership = nil
                recoverableDictationResult = nil
                forcesSessionNotRunning = true
                render()
                return
            }
            if state.sessionID != lastSeenDictationSessionID {
                cancelDocumentIdentifierRetry()
                forcesSessionNotRunning = false
                expiredAttemptReconnect = nil
                retiredDictationAttempt = nil
                authoritativeIdleReadyPublishedAt = nil
                lastSeenDictationSessionID = state.sessionID
                insertedDictationRequestID = nil
                pendingDeliveryClaimID = nil
                pendingExplicitDeliveryRequestID = nil
                activeDictationOwnership = nil
                automaticDeliveryDisqualifiedRequestID = nil
                recoverableDictationResult = nil
                allowsStateReconnection = true
            }
            retireExpiredAttemptReconnectIfReplaced(by: state)
            restoreExpiredAttemptReconnectIfEligible(for: state)
            dictationState = state
            if let identity = KeyboardDictationAttemptIdentity(state) {
                let hasDurableHandoff = hasDurableHandoffOwnership(identity)
                let wasRetired = retiredDictationAttempt == identity
                let mayReconnect = !wasRetired
                    && (pendingHandoffRequestID == identity.requestID
                        || hasDurableHandoff
                        || (allowsStateReconnection
                            && identity.belongsToDocument(
                                activeDocumentIdentifier
                            )))
                if activeDictationOwnership == nil, mayReconnect {
                    activeDictationOwnership = identity
                    allowsStateReconnection = false
                }
                if activeDictationOwnership == identity,
                   pendingHandoffRequestID == identity.requestID {
                    pendingHandoffRequestID = nil
                    handoffLaunchFailed = false
                }
                refreshAutomaticDeliveryEligibility(for: identity)
            } else if state.phase == .ready {
                cancelDocumentIdentifierRetry()
                if let activeDictationOwnership {
                    retiredDictationAttempt = activeDictationOwnership
                }
                if authoritativeIdleReadyPublishedAt.map({
                    state.publishedAt > $0
                }) ?? true {
                    authoritativeIdleReadyPublishedAt = state.publishedAt
                }
                expiredAttemptReconnect = nil
                activeDictationOwnership = nil
                automaticDeliveryRequestID = nil
                automaticDeliveryDisqualifiedRequestID = nil
                recoverableDictationResult = nil
                // An authoritative idle Ready closes every previous attempt
                // in this session. A later attempt started by this controller
                // receives explicit ownership in beginDictation; an
                // unsolicited stale state must not reconnect by document.
                allowsStateReconnection = false
                pendingDeliveryClaimID = nil
                pendingExplicitDeliveryRequestID = nil
                forcesSessionNotRunning = false
            }
            if state.phase == .listening
                || state.phase == .processing
                || state.phase == .resultReady
                || state.phase == .unavailable
                || state.phase == .failed {
                pendingDictationCommand = nil
            }
            if recoverableDictationResult?.requestID != state.requestID {
                recoverableDictationResult = nil
            }
            recordKeyboardState(diagnosticState(for: state.phase))
            if state.phase == .resultReady {
                handleResultReady(state)
            } else if (state.phase == .unavailable || state.phase == .failed),
                      owns(state) {
                cancelDocumentIdentifierRetry()
                activeDictationOwnership = nil
                automaticDeliveryRequestID = nil
                automaticDeliveryDisqualifiedRequestID = nil
                recoverableDictationResult = nil
                pendingDictationCommand = nil
                pendingDeliveryClaimID = nil
                pendingExplicitDeliveryRequestID = nil
                forcesSessionNotRunning = state.phase == .unavailable
            }
            scheduleListeningCountdownIfNeeded(for: state)
            dictationExpiryTimer = dependencies.scheduleLatestExpiry(
                state.expiresAt
            ) { [weak self] in
                guard let self,
                      self.dictationState == state else {
                    return
                }
                // The timer belongs to an observed snapshot, not to the
                // canonical bridge slot. Re-read before clearing ownership:
                // a delayed Darwin notification may have left a newer
                // Processing/Result/Failed record in the store already.
                self.reloadDictationState()
            }
        } catch {
            recordKeyboardState(.failed)
            cancelDocumentIdentifierRetry()
            dictationState = nil
            activeDictationOwnership = nil
            recoverableDictationResult = nil
            forcesSessionNotRunning = true
        }
        render()
    }

    private func scheduleListeningCountdownIfNeeded(
        for state: KeyboardDictationStateRecord
    ) {
        guard state.phase == .listening, owns(state) else { return }
        listeningCountdownTimer = dependencies.scheduleListeningCountdown {
            [weak self] in
            guard let self,
                  let currentState = self.dictationState,
                  currentState == state,
                  currentState.phase == .listening,
                  self.owns(currentState),
                  currentState.isValid(at: self.dependencies.now()) else {
                self?.cancelListeningCountdown()
                self?.render()
                return
            }
            self.render()
        }
    }

    private func cancelListeningCountdown() {
        listeningCountdownTimer?.invalidate()
        listeningCountdownTimer = nil
    }

    private func preserveExpiredAttemptReconnect() {
        guard let state = dictationState,
              state.phase == .listening || state.phase == .processing,
              let identity = activeDictationOwnership,
              identity.matches(state) else {
            return
        }
        // Listening/Processing TTLs remove a stale presentation snapshot;
        // they are not authority to reject a strictly newer terminal state
        // from the same attempt. Preserve only the immutable attempt identity.
        expiredAttemptReconnect = ExpiredAttemptReconnect(
            identity: identity,
            publishedAt: state.publishedAt
        )
    }

    private func retireExpiredAttemptReconnectIfReplaced(
        by state: KeyboardDictationStateRecord
    ) {
        guard let reconnect = expiredAttemptReconnect,
              state.sessionID == reconnect.identity.sessionID else {
            return
        }
        let hasAuthoritativeIdleReady = state.phase == .ready
            && !state.hasActiveAttempt
        let hasDifferentAttempt = KeyboardDictationAttemptIdentity(state)
            .map { $0 != reconnect.identity }
            ?? false
        guard hasAuthoritativeIdleReady || hasDifferentAttempt else { return }

        // A canonical idle state or replacement attempt is monotonic proof
        // that the expired attempt no longer owns this extension lifetime.
        retiredDictationAttempt = reconnect.identity
        expiredAttemptReconnect = nil
        forcesSessionNotRunning = false
    }

    private func restoreExpiredAttemptReconnectIfEligible(
        for state: KeyboardDictationStateRecord
    ) {
        guard forcesSessionNotRunning,
              let reconnect = expiredAttemptReconnect,
              let identity = KeyboardDictationAttemptIdentity(state),
              identity == reconnect.identity,
              state.publishedAt > reconnect.publishedAt,
              state.phase == .processing
                || state.phase == .resultReady
                || state.phase == .failed
                || state.phase == .unavailable else {
            return
        }
        activeDictationOwnership = identity
        allowsStateReconnection = false
        forcesSessionNotRunning = false
        expiredAttemptReconnect = nil
    }

    private func handleResultReady(_ state: KeyboardDictationStateRecord) {
        let documentProxy = activeDocumentProxy
        let currentDocumentID = dependencies.loadDocumentIdentifier(
            documentProxy
        )
        let sourceDocumentID = state.sourceDocumentID
        Self.deliveryLogger.info("result observed")
        recordDelivery(
            .resultObserved,
            requestID: state.requestID,
            sourceDocumentID: sourceDocumentID,
            currentDocumentID: currentDocumentID
        )
        guard let requestID = state.requestID,
              owns(state),
              let result = state.result,
              let ownership = activeDictationOwnership else {
            Self.deliveryLogger.error("result rejected before document gate")
            recordDelivery(
                .requestRejected,
                requestID: state.requestID,
                sourceDocumentID: sourceDocumentID,
                currentDocumentID: currentDocumentID
            )
            cancelDocumentIdentifierRetry()
            return
        }
        guard insertedDictationRequestID != requestID else {
            cancelDocumentIdentifierRetry()
            return
        }
        guard acceptsAutomaticDelivery else {
            Self.deliveryLogger.info(
                "result deferred while controller is inactive"
            )
            recordDelivery(
                .controllerInactive,
                requestID: requestID,
                sourceDocumentID: ownership.sourceDocumentID,
                currentDocumentID: currentDocumentID
            )
            cancelDocumentIdentifierRetry()
            return
        }
        if pendingExplicitDeliveryRequestID == requestID {
            guard let grantedClaimID = state.deliveryClaimID else {
                return
            }
            guard pendingDeliveryClaimID == grantedClaimID else {
                Self.deliveryLogger.error(
                    "explicit delivery grant has no local claim"
                )
                recordDelivery(
                    .grantRejected,
                    requestID: requestID,
                    claimID: grantedClaimID,
                    sourceDocumentID: ownership.sourceDocumentID,
                    currentDocumentID: currentDocumentID
                )
                pendingDeliveryClaimID = nil
                pendingExplicitDeliveryRequestID = nil
                exposeRecoverableResult(requestID: requestID, result: result)
                return
            }
            consumeGrantedDelivery(
                result: result,
                requestID: requestID,
                claimID: grantedClaimID,
                documentProxy: documentProxy,
                sourceDocumentID: ownership.sourceDocumentID,
                currentDocumentID: currentDocumentID,
                isExplicitRecovery: true
            )
            return
        }
        guard automaticDeliveryRequestID == requestID else {
            Self.deliveryLogger.info("originating controller is unavailable")
            recordDelivery(
                .controllerLifetimeLost,
                requestID: requestID,
                sourceDocumentID: ownership.sourceDocumentID,
                currentDocumentID: currentDocumentID
            )
            disqualifyAutomaticDelivery(
                requestID: requestID,
                result: result
            )
            return
        }
        guard automaticDeliveryDisqualifiedRequestID != requestID else {
            recordDelivery(
                .deliveryPreviouslyDisqualified,
                requestID: requestID,
                sourceDocumentID: ownership.sourceDocumentID,
                currentDocumentID: currentDocumentID
            )
            exposeRecoverableResult(requestID: requestID, result: result)
            cancelDocumentIdentifierRetry()
            return
        }
        guard let immutableSourceDocumentID = ownership.sourceDocumentID else {
            Self.deliveryLogger.info("source document unavailable")
            recordDelivery(
                .documentMissing,
                requestID: requestID,
                sourceDocumentID: nil,
                currentDocumentID: currentDocumentID
            )
            disqualifyAutomaticDelivery(
                requestID: requestID,
                result: result
            )
            return
        }
        guard let currentDocumentID else {
            Self.deliveryLogger.info("current document unavailable")
            recordDelivery(
                .documentMissing,
                requestID: requestID,
                sourceDocumentID: immutableSourceDocumentID,
                currentDocumentID: nil
            )
            if documentIdentifierRetryCount
                < Self.maximumDocumentIdentifierRetryCount {
                scheduleDocumentIdentifierRetry(for: requestID)
            } else {
                disqualifyAutomaticDelivery(
                    requestID: requestID,
                    result: result
                )
            }
            return
        }
        guard immutableSourceDocumentID == currentDocumentID else {
            Self.deliveryLogger.error("document gate rejected result")
            recordDelivery(
                .documentMismatch,
                requestID: requestID,
                sourceDocumentID: immutableSourceDocumentID,
                currentDocumentID: currentDocumentID
            )
            disqualifyAutomaticDelivery(
                requestID: requestID,
                result: result
            )
            return
        }
        recordDelivery(
            .documentMatched,
            requestID: requestID,
            sourceDocumentID: immutableSourceDocumentID,
            currentDocumentID: currentDocumentID
        )
        cancelDocumentIdentifierRetry()
        recoverableDictationResult = nil
        if let grantedClaimID = state.deliveryClaimID {
            guard pendingDeliveryClaimID == grantedClaimID else {
                Self.deliveryLogger.error("delivery grant has no local claim")
                recordDelivery(
                    .grantRejected,
                    requestID: requestID,
                    claimID: grantedClaimID,
                    sourceDocumentID: ownership.sourceDocumentID,
                    currentDocumentID: currentDocumentID
                )
                disqualifyAutomaticDelivery(
                    requestID: requestID,
                    result: result
                )
                return
            }
            consumeGrantedDelivery(
                result: result,
                requestID: requestID,
                claimID: grantedClaimID,
                documentProxy: documentProxy,
                sourceDocumentID: ownership.sourceDocumentID,
                currentDocumentID: currentDocumentID,
                isExplicitRecovery: false
            )
        } else if pendingDeliveryClaimID == nil {
            let claimID = dependencies.makeDeliveryClaimID()
            pendingDeliveryClaimID = claimID
            Self.deliveryLogger.info("delivery claim requested")
            recordDelivery(
                .claimRequested,
                requestID: requestID,
                claimID: claimID,
                sourceDocumentID: ownership.sourceDocumentID,
                currentDocumentID: currentDocumentID
            )
            if !sendDictationCommand(
                .claimDelivery,
                deliveryClaimID: claimID
            ) {
                Self.deliveryLogger.error("delivery claim could not be sent")
                pendingDeliveryClaimID = nil
            }
        }
    }

    private func consumeGrantedDelivery(
        result: String,
        requestID: UUID,
        claimID: UUID,
        documentProxy: any UITextDocumentProxy,
        sourceDocumentID: UUID?,
        currentDocumentID: UUID?,
        isExplicitRecovery: Bool
    ) {
        Self.deliveryLogger.info("delivery grant accepted")
        recordDelivery(
            .grantAccepted,
            requestID: requestID,
            claimID: claimID,
            sourceDocumentID: sourceDocumentID,
            currentDocumentID: currentDocumentID
        )
        insertedDictationRequestID = requestID
        recoverableDictationResult = nil
        beginDeliveryObservation(requestID: requestID, claimID: claimID)
        recordDelivery(
            .insertInvoked,
            requestID: requestID,
            claimID: claimID,
            sourceDocumentID: sourceDocumentID,
            currentDocumentID: currentDocumentID
        )
        dependencies.recordDiagnostic(
            .keyboardInsertInvoked(
                isExplicitRecovery ? .latest : .dictation
            )
        )
        insertText(result, into: documentProxy)
        recordDelivery(
            .insertReturned,
            requestID: requestID,
            claimID: claimID,
            sourceDocumentID: sourceDocumentID,
            currentDocumentID: currentDocumentID
        )
        scheduleDeliveryObservationTimeout(
            requestID: requestID,
            claimID: claimID
        )
        Self.deliveryLogger.info("document proxy insertion requested")
        recordDelivery(
            .acknowledgementRequested,
            requestID: requestID,
            claimID: claimID,
            sourceDocumentID: sourceDocumentID,
            currentDocumentID: currentDocumentID
        )
        _ = sendDictationCommand(
            .acknowledgeDelivery,
            deliveryClaimID: claimID
        )
        pendingDeliveryClaimID = nil
        pendingExplicitDeliveryRequestID = nil
    }

    private func disqualifyAutomaticDelivery(
        requestID: UUID,
        result: String
    ) {
        automaticDeliveryDisqualifiedRequestID = requestID
        pendingDeliveryClaimID = nil
        pendingExplicitDeliveryRequestID = nil
        cancelDocumentIdentifierRetry()
        exposeRecoverableResult(requestID: requestID, result: result)
    }

    private func exposeRecoverableResult(
        requestID: UUID,
        result: String
    ) {
        recoverableDictationResult = (requestID, result)
    }

    private func scheduleDocumentIdentifierRetry(for requestID: UUID) {
        if documentIdentifierRetryRequestID != requestID {
            cancelDocumentIdentifierRetry()
            documentIdentifierRetryRequestID = requestID
        }
        guard !documentIdentifierRetryIsScheduled,
              documentIdentifierRetryCount
                < Self.maximumDocumentIdentifierRetryCount else {
            return
        }
        documentIdentifierRetryIsScheduled = true
        documentIdentifierRetryTimer =
            dependencies.scheduleDocumentIdentifierRetry { [weak self] in
                guard let self else { return }
                documentIdentifierRetryTimer = nil
                documentIdentifierRetryIsScheduled = false
                guard dictationState?.requestID == requestID else {
                    cancelDocumentIdentifierRetry()
                    return
                }
                documentIdentifierRetryCount += 1
                reloadDictationState()
            }
    }

    private func cancelDocumentIdentifierRetry() {
        documentIdentifierRetryTimer?.invalidate()
        documentIdentifierRetryTimer = nil
        documentIdentifierRetryRequestID = nil
        documentIdentifierRetryCount = 0
        documentIdentifierRetryIsScheduled = false
    }

    private func beginDeliveryObservation(
        requestID: UUID,
        claimID: UUID
    ) {
        cancelDeliveryObservation()
        pendingDeliveryObservation = (requestID, claimID)
    }

    private func scheduleDeliveryObservationTimeout(
        requestID: UUID,
        claimID: UUID
    ) {
        guard pendingDeliveryObservation?.requestID == requestID,
              pendingDeliveryObservation?.claimID == claimID else {
            return
        }
        deliveryObservationTimer = dependencies.scheduleDeliveryObservation {
            [weak self] in
            guard let self,
                  pendingDeliveryObservation?.requestID == requestID,
                  pendingDeliveryObservation?.claimID == claimID else {
                return
            }
            recordDelivery(
                .textChangeNotObserved,
                requestID: requestID,
                claimID: claimID,
                sourceDocumentID: activeDictationOwnership?.sourceDocumentID,
                currentDocumentID: activeDocumentIdentifier
            )
            cancelDeliveryObservation()
        }
    }

    private func cancelDeliveryObservation() {
        deliveryObservationTimer?.invalidate()
        deliveryObservationTimer = nil
        pendingDeliveryObservation = nil
    }

    private func handleMicrophoneCommand() {
        guard hasSharedContainerAccess else {
            openFullAccessSettings()
            return
        }
        guard !forcesSessionNotRunning, let state = dictationState else {
            beginHandoff()
            return
        }
        switch state.phase {
        case .ready:
            if state.hasActiveAttempt {
                if owns(state) {
                    return
                }
                beginHandoff()
            } else {
                beginDictation(action: automaticVoiceAction)
            }
        case .listening:
            if owns(state) {
                sendDictationCommand(.finish)
            } else {
                beginHandoff()
            }
        case .processing:
            if !owns(state) {
                beginHandoff()
            }
        case .resultReady, .unavailable, .failed:
            beginHandoff()
        }
    }

    private func beginHandoff() {
        guard pendingHandoffRequestID == nil else { return }
        let issuedAt = dependencies.now()
        let requestID = dependencies.makeRequestID()
        guard let intent = KeyboardHandoffIntentRecord(
            requestID: requestID,
            sourceDocumentID: activeDocumentIdentifier,
            action: automaticVoiceAction,
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(
                KeyboardHandoffIntentConfiguration.lifetime
            )
        ), let url = KeyboardHandoffLaunchRoute(requestID: requestID).url else {
            handoffLaunchFailed = true
            render()
            return
        }
        do {
            try dependencies.saveHandoffIntent(intent)
        } catch {
            handoffLaunchFailed = true
            render()
            return
        }
        automaticDeliveryRequestID = requestID
        automaticDeliveryDisqualifiedRequestID = nil
        recoverableDictationResult = nil
        pendingHandoffRequestID = requestID
        handoffLaunchFailed = false
        render()
        openContainingApp(url) { [weak self] in
            guard let self,
                  pendingHandoffRequestID == requestID else { return }
            pendingHandoffRequestID = nil
            handoffLaunchFailed = true
            render()
        }
    }

    private func beginDictation(action: KeyboardVoiceAction) {
        guard let state = dictationState,
              state.phase == .ready,
              !state.hasActiveAttempt else {
            return
        }
        if action.translates, !state.translationAvailable {
            openTranslationSettings()
            return
        }
        let documentProxy = activeDocumentProxy
        let sourceDocumentID = dependencies.loadDocumentIdentifier(
            documentProxy
        )
        let requestID = dependencies.makeRequestID()
        activeDictationOwnership = KeyboardDictationAttemptIdentity(
            sessionID: state.sessionID,
            attemptID: dependencies.makeAttemptID(),
            requestID: requestID,
            sourceDocumentID: sourceDocumentID
        )
        automaticDeliveryRequestID = requestID
        automaticDeliveryDisqualifiedRequestID = sourceDocumentID == nil
            ? requestID
            : nil
        recoverableDictationResult = nil
        allowsStateReconnection = false
        sendDictationCommand(.start, action: action)
    }

    private func selectAutomaticVoiceAction(_ action: KeyboardVoiceAction) {
        if action.translates,
           dictationState?.phase == .ready,
           dictationState?.translationAvailable == false {
            openTranslationSettings()
            return
        }
        automaticVoiceAction = action
        render()
    }

    private func openHistory() {
        guard let url = KeyboardHistoryLaunchRoute().url else { return }
        openContainingApp(url) {
            UIAccessibility.post(
                notification: .announcement,
                argument: "Could not open HoldType History."
            )
        }
    }

    private func openTranslationSettings() {
        guard let url = URL(string: "holdtype://settings/translation") else {
            return
        }
        openContainingApp(url) {
            UIAccessibility.post(
                notification: .announcement,
                argument: "Could not open HoldType Translation Settings."
            )
        }
    }

    private func openFullAccessSettings() {
        guard let url = URL(string: "holdtype://settings/fullAccess") else {
            return
        }
        openContainingApp(url) {
            UIAccessibility.post(
                notification: .announcement,
                argument: "Could not open HoldType Full Access setup."
            )
        }
    }

    private func openContainingApp(
        _ url: URL,
        onFailure: @escaping @MainActor () -> Void
    ) {
        let completion: (Bool) -> Void = { didOpen in
            guard !didOpen else { return }
            Task { @MainActor in
                onFailure()
            }
        }
        if let openContainingAppOverride = dependencies.openContainingAppOverride {
            openContainingAppOverride(url, completion)
        } else {
            KeyboardContainingAppLaunchAdapter.open(
                url,
                from: self,
                extensionContext: extensionContext,
                completion: completion
            )
        }
    }

    @discardableResult
    private func sendDictationCommand(
        _ kind: KeyboardDictationCommandKind,
        action: KeyboardVoiceAction = .standard,
        deliveryClaimID: UUID? = nil
    ) -> Bool {
        guard hasSharedContainerAccess,
              let state = dictationState,
              state.expiresAt > dependencies.now(),
              let ownership = activeDictationOwnership,
              ownership.sessionID == state.sessionID,
              (kind == .start
                || ownership.matches(state)
                || (kind == .cancel
                    && pendingDictationCommand == .start)) else {
            return false
        }
        let now = dependencies.now()
        guard let command = KeyboardDictationCommandRecord(
            sessionID: ownership.sessionID,
            attemptID: ownership.attemptID,
            requestID: ownership.requestID,
            sourceDocumentID: ownership.sourceDocumentID,
            deliveryClaimID: deliveryClaimID,
            kind: kind,
            action: action,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(
                KeyboardDictationBridgeConfiguration.commandLifetime
            )
        ) else {
            return false
        }
        do {
            try dependencies.saveDictationCommand(command)
            dependencies.recordDiagnostic(
                .keyboardCommand(
                    diagnosticCommand(kind),
                    action: diagnosticAction(action),
                    outcome: .succeeded
                )
            )
            if kind == .start || kind == .finish {
                pendingDictationCommand = kind
            } else if kind == .cancel {
                activeDictationOwnership = nil
                automaticDeliveryRequestID = nil
                automaticDeliveryDisqualifiedRequestID = nil
                recoverableDictationResult = nil
                pendingDictationCommand = nil
                pendingDeliveryClaimID = nil
                pendingExplicitDeliveryRequestID = nil
                forcesSessionNotRunning = true
            }
        } catch {
            dependencies.recordDiagnostic(
                .keyboardCommand(
                    diagnosticCommand(kind),
                    action: diagnosticAction(action),
                    outcome: .failed
                )
            )
            pendingDictationCommand = nil
            pendingDeliveryClaimID = nil
            pendingExplicitDeliveryRequestID = nil
            activeDictationOwnership = nil
            automaticDeliveryRequestID = nil
            automaticDeliveryDisqualifiedRequestID = nil
            recoverableDictationResult = nil
            forcesSessionNotRunning = true
            render()
            return false
        }
        render()
        return true
    }

    private var returnIsEnabled: Bool {
        !((activeDocumentProxy.enablesReturnKeyAutomatically ?? false)
            && !activeDocumentProxy.hasText)
    }

    private func insert(_ item: KeyboardBridgeItem) {
        insertText(item.text)
        dependencies.recordDiagnostic(.keyboardInsertInvoked(.latest))
    }

    private func insertLatestOrRecoverableResult() {
        if let recoverableDictationResult {
            guard acceptsAutomaticDelivery,
                  pendingExplicitDeliveryRequestID == nil,
                  pendingDeliveryClaimID == nil,
                  let state = dictationState,
                  state.phase == .resultReady,
                  state.requestID == recoverableDictationResult.requestID,
                  owns(state) else {
                return
            }
            cancelDocumentIdentifierRetry()
            pendingExplicitDeliveryRequestID =
                recoverableDictationResult.requestID
            if let grantedClaimID = state.deliveryClaimID {
                pendingDeliveryClaimID = grantedClaimID
                handleResultReady(state)
                return
            }
            let claimID = dependencies.makeDeliveryClaimID()
            pendingDeliveryClaimID = claimID
            if !sendDictationCommand(
                .claimDelivery,
                deliveryClaimID: claimID
            ) {
                pendingDeliveryClaimID = nil
                pendingExplicitDeliveryRequestID = nil
            }
            return
        }
        guard let latestItem else { return }
        insert(latestItem)
    }

    private func beginExtensionLifetime() {
        acceptsAutomaticDelivery = true
        activeDictationOwnership = nil
        expiredAttemptReconnect = nil
        retiredDictationAttempt = nil
        authoritativeIdleReadyPublishedAt = nil
        allowsStateReconnection = true
        pendingDictationCommand = nil
        pendingDeliveryClaimID = nil
        pendingExplicitDeliveryRequestID = nil
        pendingHandoffRequestID = nil
        handoffLaunchFailed = false
        forcesSessionNotRunning = false
        automaticVoiceAction = .standard
    }

    private func endExtensionLifetime() {
        acceptsAutomaticDelivery = false
        activeDictationOwnership = nil
        expiredAttemptReconnect = nil
        retiredDictationAttempt = nil
        authoritativeIdleReadyPublishedAt = nil
        allowsStateReconnection = true
        pendingDictationCommand = nil
        pendingDeliveryClaimID = nil
        pendingExplicitDeliveryRequestID = nil
        pendingHandoffRequestID = nil
        forcesSessionNotRunning = false
    }

    private func refreshAutomaticDeliveryEligibility(
        for preferredIdentity: KeyboardDictationAttemptIdentity? = nil
    ) {
        let stateIdentity = dictationState.flatMap(
            KeyboardDictationAttemptIdentity.init
        )
        guard let identity = [
            preferredIdentity,
            activeDictationOwnership,
            stateIdentity,
        ].compactMap({ $0 }).first else {
            return
        }
        let hasDurableHandoff = hasDurableHandoffOwnership(identity)
        if automaticDeliveryRequestID == nil, hasDurableHandoff {
            automaticDeliveryRequestID = identity.requestID
        }
        guard automaticDeliveryRequestID == identity.requestID,
              automaticDeliveryDisqualifiedRequestID != identity.requestID
        else { return }
        guard let sourceDocumentIdentifier = identity.sourceDocumentID else {
            automaticDeliveryDisqualifiedRequestID = identity.requestID
            if pendingExplicitDeliveryRequestID != identity.requestID {
                pendingDeliveryClaimID = nil
            }
            cancelDocumentIdentifierRetry()
            return
        }
        let currentDocumentIdentifier = activeDocumentIdentifier
        if let currentDocumentIdentifier,
           sourceDocumentIdentifier != currentDocumentIdentifier {
            recordDelivery(
                .documentMismatch,
                requestID: identity.requestID,
                sourceDocumentID: identity.sourceDocumentID,
                currentDocumentID: currentDocumentIdentifier
            )
            automaticDeliveryDisqualifiedRequestID =
                identity.requestID
            if pendingExplicitDeliveryRequestID != identity.requestID {
                pendingDeliveryClaimID = nil
            }
            cancelDocumentIdentifierRetry()
        }
    }

    /// A consumed handoff is the durable control token for one app-admitted
    /// request. It lets a recreated extension finish capture even when UIKit
    /// temporarily withholds the document UUID. Automatic insertion remains
    /// independently gated by the immutable source document identifier.
    private func hasDurableHandoffOwnership(
        _ identity: KeyboardDictationAttemptIdentity
    ) -> Bool {
        guard let intent = try? dependencies.loadConsumedHandoffIntent() else {
            return false
        }
        guard intent.requestID == identity.requestID,
              intent.sourceDocumentID == identity.sourceDocumentID else {
            return false
        }
        guard let authoritativeIdleReadyPublishedAt else { return true }
        guard let consumedAt = intent.consumedAt else { return false }
        return consumedAt > authoritativeIdleReadyPublishedAt
    }

    private func owns(_ state: KeyboardDictationStateRecord) -> Bool {
        activeDictationOwnership?.matches(state) == true
    }

    private func insertText(_ text: String) {
        insertText(text, into: activeDocumentProxy)
    }

    private func insertText(
        _ text: String,
        into documentProxy: any UITextDocumentProxy
    ) {
        guard insertionGate.beginEvent() else { return }
        defer { insertionGate.endEvent() }
        documentProxy.insertText(text)
    }

    private func recordKeyboardState(_ state: IOSDiagnosticKeyboardState) {
        guard lastDiagnosticState != state else { return }
        lastDiagnosticState = state
        dependencies.recordDiagnostic(.keyboardState(state))
    }

    private func recordDelivery(
        _ stage: IOSDiagnosticKeyboardDeliveryStage,
        requestID: UUID?,
        claimID: UUID? = nil,
        sourceDocumentID: UUID?,
        currentDocumentID: UUID?
    ) {
        dependencies.recordDiagnostic(
            .keyboardDelivery(
                stage,
                request: requestID.map(IOSDiagnosticCorrelationTag.init),
                claim: claimID.map(IOSDiagnosticCorrelationTag.init),
                sourceDocument: sourceDocumentID.map(
                    IOSDiagnosticCorrelationTag.init
                ),
                currentDocument: currentDocumentID.map(
                    IOSDiagnosticCorrelationTag.init
                ),
                controllerLifetime: IOSDiagnosticCorrelationTag(
                    controllerLifetimeID
                )
            )
        )
    }

    private func diagnosticState(
        for phase: KeyboardDictationStatePhase
    ) -> IOSDiagnosticKeyboardState {
        switch phase {
        case .ready:
            .sessionReady
        case .listening:
            .listening
        case .processing:
            .processing
        case .resultReady:
            .resultReady
        case .unavailable:
            .sessionUnavailable
        case .failed:
            .failed
        }
    }

    private func diagnosticCommand(
        _ kind: KeyboardDictationCommandKind
    ) -> IOSDiagnosticKeyboardCommand {
        switch kind {
        case .start:
            .start
        case .finish:
            .finish
        case .cancel:
            .cancel
        case .claimDelivery:
            .claimDelivery
        case .acknowledgeDelivery:
            .acknowledgeDelivery
        }
    }

    private func diagnosticAction(
        _ action: KeyboardVoiceAction
    ) -> IOSDiagnosticVoiceAction {
        switch action {
        case .standard:
            .standard
        case .translate:
            .translate
        case .improve:
            .improve
        case .translateAndImprove:
            .translateAndImprove
        }
    }

    private func setLatestItem(_ item: KeyboardBridgeItem?) {
        latestItem = item
    }

    private func handleCursorGesture(
        state: UIGestureRecognizer.State,
        locationX: CGFloat
    ) {
        switch state {
        case .began:
            cursorAccumulator.reset()
            previousCursorLocationX = locationX
        case .changed:
            guard let previousCursorLocationX else { return }
            self.previousCursorLocationX = locationX
            if let movement = cursorAccumulator.consume(
                horizontalDelta: Double(locationX - previousCursorLocationX)
            ) {
                activeDocumentProxy.adjustTextPosition(
                    byCharacterOffset: movement.characterOffset
                )
            }
        case .ended, .cancelled, .failed:
            cursorAccumulator.reset()
            previousCursorLocationX = nil
        default:
            break
        }
    }

    private static func returnSemantic(
        for returnKeyType: UIReturnKeyType
    ) -> KeyboardReturnKeySemantic {
        switch returnKeyType {
        case .go:
            .go
        case .google, .search, .yahoo:
            .search
        case .join:
            .join
        case .next:
            .next
        case .route:
            .route
        case .send:
            .send
        case .done:
            .done
        case .emergencyCall:
            .emergencyCall
        case .continue:
            .continueAction
        case .default:
            .lineBreak
        @unknown default:
            .lineBreak
        }
    }
}

@MainActor
private final class KeyboardDeleteRepeater {
    private let profile = KeyboardDeleteRepeatProfile()
    private var timer: Timer?
    private var completedRepeats = 0
    private var action: (() -> Void)?

    isolated deinit {
        stop()
    }

    func start(action: @escaping () -> Void) {
        stop()
        self.action = action
        action()
        schedule(after: profile.initialDelay)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        completedRepeats = 0
        action = nil
    }

    private func schedule(after interval: TimeInterval) {
        let timer = Timer(
            timeInterval: interval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fire()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func fire() {
        guard let action else { return }
        action()
        completedRepeats += 1
        schedule(
            after: profile.interval(
                afterCompletedRepeats: completedRepeats
            )
        )
    }
}
