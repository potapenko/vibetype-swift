import OSLog
import UIKit

typealias KeyboardLatestExpiryScheduler = (
    Date,
    @escaping @MainActor () -> Void
) -> Timer?

typealias KeyboardDocumentIdentifierRetryScheduler = (
    @escaping @MainActor () -> Void
) -> Timer?

typealias KeyboardDeliveryObservationScheduler = (
    @escaping @MainActor () -> Void
) -> Timer?

typealias KeyboardContainingAppOpener = (
    URL,
    @escaping (Bool) -> Void
) -> Void

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

@MainActor
struct KeyboardViewControllerDependencies {
    let loadSnapshot: () throws -> KeyboardBridgeSnapshot?
    let loadDictationState: () throws -> KeyboardDictationStateRecord?
    let loadConsumedHandoffIntent: () throws -> KeyboardHandoffIntentRecord?
    let saveDictationCommand: (KeyboardDictationCommandRecord) throws -> Void
    let saveHandoffIntent: (KeyboardHandoffIntentRecord) throws -> Void
    let observeDictationState: (
        @escaping @MainActor () -> Void
    ) -> KeyboardDictationBridgeObserver?
    let now: () -> Date
    let makeRequestID: () -> UUID
    let makeAttemptID: () -> UUID
    let makeDeliveryClaimID: () -> UUID
    let documentProxyOverride: (any UITextDocumentProxy)?
    let loadDocumentIdentifier: (any UITextDocumentProxy) -> UUID?
    let inputModeSwitchKeyOverride: Bool?
    let fullAccessOverride: Bool?
    let scheduleLatestExpiry: KeyboardLatestExpiryScheduler
    let scheduleDocumentIdentifierRetry:
        KeyboardDocumentIdentifierRetryScheduler
    let scheduleDeliveryObservation: KeyboardDeliveryObservationScheduler
    let openContainingAppOverride: KeyboardContainingAppOpener?
    let recordDiagnostic: (IOSRuntimeDiagnosticEvent) -> Void

    static let live = KeyboardViewControllerDependencies(
        loadSnapshot: {
            let store = try KeyboardBridgeStore.appGroup()
            return try store.load()
        },
        loadDictationState: {
            let store = try KeyboardDictationBridgeStore.appGroup()
            return try store.loadState()
        },
        loadConsumedHandoffIntent: {
            let store = try KeyboardHandoffIntentStore.appGroup()
            return try store.loadConsumed()
        },
        saveDictationCommand: { command in
            let store = try KeyboardDictationBridgeStore.appGroup()
            try store.saveCommand(command)
            KeyboardDictationBridgeSignal.postCommandChanged()
        },
        saveHandoffIntent: { intent in
            let store = try KeyboardHandoffIntentStore.appGroup()
            try store.save(intent)
        },
        observeDictationState: { action in
            KeyboardDictationBridgeObserver(
                name: KeyboardDictationBridgeConfiguration.stateNotification,
                action: action
            )
        },
        now: { Date() },
        makeRequestID: { UUID() },
        makeAttemptID: { UUID() },
        makeDeliveryClaimID: { UUID() },
        documentProxyOverride: nil,
        loadDocumentIdentifier: { documentProxy in
            KeyboardDocumentIdentifierAdapter.load(from: documentProxy)
        },
        inputModeSwitchKeyOverride: nil,
        fullAccessOverride: nil,
        scheduleLatestExpiry: { fireDate, action in
            let timer = Timer(
                fire: fireDate,
                interval: 0,
                repeats: false
            ) { _ in
                Task { @MainActor in
                    action()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            return timer
        },
        scheduleDocumentIdentifierRetry: { action in
            let timer = Timer(
                timeInterval: 0.1,
                repeats: false
            ) { _ in
                Task { @MainActor in
                    action()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            return timer
        },
        scheduleDeliveryObservation: { action in
            let timer = Timer(
                timeInterval: 0.5,
                repeats: false
            ) { _ in
                Task { @MainActor in
                    action()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            return timer
        },
        openContainingAppOverride: nil,
        recordDiagnostic: { event in
            IOSRuntimeDiagnosticsStore.keyboard.record(event)
        }
    )
}

final class KeyboardViewController: UIInputViewController {
    private static let maximumDocumentIdentifierRetryCount = 20
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
    private var insertedDictationRequestID: UUID?
    private var pendingDeliveryClaimID: UUID?
    private var lastSeenDictationSessionID: UUID?
    private var pendingDictationCommand: KeyboardDictationCommandKind?
    private var pendingHandoffRequestID: UUID?
    private var handoffLaunchFailed = false
    private var forcesSessionNotRunning = false
    private var showsInputModeSwitchKey = true
    private var allowsStateReconnection = true
    private var automaticVoiceAction: KeyboardVoiceAction = .standard

    convenience init(dependencies: KeyboardViewControllerDependencies) {
        self.init(nibName: nil, bundle: nil)
        self.dependencies = dependencies
    }

    private var activeDocumentProxy: any UITextDocumentProxy {
        dependencies.documentProxyOverride ?? textDocumentProxy
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
        hasDictationKey = true
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
        recordKeyboardState(.opened)
        beginExtensionLifetime()
        showsInputModeSwitchKey = shouldShowInputModeSwitchKey
        reloadSharedSnapshot()
        reloadDictationState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        recordKeyboardState(.closed)
        deleteRepeater.stop()
        dictationExpiryTimer?.invalidate()
        dictationExpiryTimer = nil
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
            recordDelivery(
                .textWillChange,
                requestID: observation.requestID,
                claimID: observation.claimID,
                proxyHasText: activeDocumentProxy.hasText
            )
        }
        refreshStateReconnectionEligibility()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if let observation = pendingDeliveryObservation {
            recordDelivery(
                .textDidChange,
                requestID: observation.requestID,
                claimID: observation.claimID,
                proxyHasText: activeDocumentProxy.hasText
            )
            cancelDeliveryObservation()
        }
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
        keyboardView.onLatestRequested = { [weak self] in
            guard let self, let latestItem else { return }
            insert(latestItem)
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
                automaticVoiceAction: automaticVoiceAction,
                latestIsEnabled: latestItem != nil,
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
        guard hasSharedContainerAccess else {
            dictationState = nil
            activeDictationOwnership = nil
            pendingDictationCommand = nil
            render()
            return
        }
        do {
            guard let state = try dependencies.loadDictationState(),
                  state.isValid(at: dependencies.now()) else {
                recordKeyboardState(.expired)
                cancelDocumentIdentifierRetry()
                dictationState = nil
                activeDictationOwnership = nil
                forcesSessionNotRunning = true
                render()
                return
            }
            if state.sessionID != lastSeenDictationSessionID {
                cancelDocumentIdentifierRetry()
                forcesSessionNotRunning = false
                lastSeenDictationSessionID = state.sessionID
                insertedDictationRequestID = nil
                pendingDeliveryClaimID = nil
                activeDictationOwnership = nil
                allowsStateReconnection = true
            }
            dictationState = state
            if let identity = KeyboardDictationAttemptIdentity(state) {
                let mayReconnect = pendingHandoffRequestID
                    == identity.requestID
                    || (allowsStateReconnection
                        && (hasDurableHandoffOwnership(identity)
                            || identity.belongsToDocument(
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
            } else if state.phase == .ready {
                cancelDocumentIdentifierRetry()
                activeDictationOwnership = nil
                allowsStateReconnection = true
                pendingDeliveryClaimID = nil
            }
            if state.phase == .listening
                || state.phase == .processing
                || state.phase == .resultReady
                || state.phase == .unavailable
                || state.phase == .failed {
                pendingDictationCommand = nil
            }
            recordKeyboardState(diagnosticState(for: state.phase))
            if state.phase == .resultReady {
                handleResultReady(state)
            } else if (state.phase == .unavailable || state.phase == .failed),
                      owns(state) {
                cancelDocumentIdentifierRetry()
                activeDictationOwnership = nil
                pendingDictationCommand = nil
                pendingDeliveryClaimID = nil
                forcesSessionNotRunning = state.phase == .unavailable
            }
            dictationExpiryTimer = dependencies.scheduleLatestExpiry(
                state.expiresAt
            ) { [weak self] in
                guard let self,
                      self.dictationState == state else {
                    return
                }
                self.dictationState = nil
                self.cancelDocumentIdentifierRetry()
                self.activeDictationOwnership = nil
                self.pendingDictationCommand = nil
                self.pendingDeliveryClaimID = nil
                self.forcesSessionNotRunning = true
                self.recordKeyboardState(.expired)
                self.render()
            }
        } catch {
            recordKeyboardState(.failed)
            cancelDocumentIdentifierRetry()
            dictationState = nil
            activeDictationOwnership = nil
            forcesSessionNotRunning = true
        }
        render()
    }

    private func handleResultReady(_ state: KeyboardDictationStateRecord) {
        Self.deliveryLogger.info("result observed")
        recordDelivery(.resultObserved, requestID: state.requestID)
        guard let requestID = state.requestID,
              owns(state),
              insertedDictationRequestID != requestID,
              let result = state.result,
              let ownership = activeDictationOwnership else {
            Self.deliveryLogger.error("result rejected before document gate")
            recordDelivery(.requestRejected, requestID: state.requestID)
            cancelDocumentIdentifierRetry()
            return
        }
        let currentDocumentID = activeDocumentIdentifier
        guard ownership.belongsToDocument(currentDocumentID) else {
            if currentDocumentID == nil, ownership.sourceDocumentID != nil {
                Self.deliveryLogger.info("document unavailable; retry scheduled")
                recordDelivery(.documentMissing, requestID: requestID)
                scheduleDocumentIdentifierRetry(for: requestID)
            } else {
                Self.deliveryLogger.error("document gate rejected result")
                recordDelivery(.documentMismatch, requestID: requestID)
                cancelDocumentIdentifierRetry()
            }
            return
        }
        recordDelivery(.documentMatched, requestID: requestID)
        cancelDocumentIdentifierRetry()
        if let grantedClaimID = state.deliveryClaimID {
            guard pendingDeliveryClaimID == grantedClaimID else {
                Self.deliveryLogger.error("delivery grant has no local claim")
                recordDelivery(
                    .grantRejected,
                    requestID: requestID,
                    claimID: grantedClaimID
                )
                return
            }
            Self.deliveryLogger.info("delivery grant accepted")
            recordDelivery(
                .grantAccepted,
                requestID: requestID,
                claimID: grantedClaimID
            )
            insertedDictationRequestID = requestID
            beginDeliveryObservation(
                requestID: requestID,
                claimID: grantedClaimID
            )
            recordDelivery(
                .insertInvoked,
                requestID: requestID,
                claimID: grantedClaimID,
                proxyHasText: activeDocumentProxy.hasText
            )
            insertText(result)
            recordDelivery(
                .insertReturned,
                requestID: requestID,
                claimID: grantedClaimID,
                proxyHasText: activeDocumentProxy.hasText
            )
            scheduleDeliveryObservationTimeout(
                requestID: requestID,
                claimID: grantedClaimID
            )
            Self.deliveryLogger.info("document proxy insertion requested")
            dependencies.recordDiagnostic(.keyboardInserted(.dictation))
            recordDelivery(
                .acknowledgementRequested,
                requestID: requestID,
                claimID: grantedClaimID
            )
            _ = sendDictationCommand(
                .acknowledgeDelivery,
                deliveryClaimID: grantedClaimID
            )
            pendingDeliveryClaimID = nil
        } else if pendingDeliveryClaimID == nil {
            let claimID = dependencies.makeDeliveryClaimID()
            pendingDeliveryClaimID = claimID
            Self.deliveryLogger.info("delivery claim requested")
            recordDelivery(
                .claimRequested,
                requestID: requestID,
                claimID: claimID
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
                proxyHasText: activeDocumentProxy.hasText
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
        activeDictationOwnership = KeyboardDictationAttemptIdentity(
            sessionID: state.sessionID,
            attemptID: dependencies.makeAttemptID(),
            requestID: dependencies.makeRequestID(),
            sourceDocumentID: activeDocumentIdentifier
        )
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
                pendingDictationCommand = nil
                pendingDeliveryClaimID = nil
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
            activeDictationOwnership = nil
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
        dependencies.recordDiagnostic(.keyboardInserted(.latest))
    }

    private func beginExtensionLifetime() {
        activeDictationOwnership = nil
        allowsStateReconnection = true
        pendingDictationCommand = nil
        pendingDeliveryClaimID = nil
        pendingHandoffRequestID = nil
        handoffLaunchFailed = false
        automaticVoiceAction = .standard
    }

    private func endExtensionLifetime() {
        activeDictationOwnership = nil
        allowsStateReconnection = true
        pendingDictationCommand = nil
        pendingDeliveryClaimID = nil
        pendingHandoffRequestID = nil
    }

    private func refreshStateReconnectionEligibility() {
        guard let activeDictationOwnership else { return }
        if !activeDictationOwnership.belongsToDocument(
            activeDocumentIdentifier
        ), !hasDurableHandoffOwnership(activeDictationOwnership) {
            self.activeDictationOwnership = nil
            allowsStateReconnection = true
            pendingDeliveryClaimID = nil
        }
    }

    /// A consumed handoff is the durable control token for one app-admitted
    /// request. It lets a recreated extension finish capture even when UIKit
    /// temporarily withholds the document UUID. Automatic insertion remains
    /// independently gated by an exact document match.
    private func hasDurableHandoffOwnership(
        _ identity: KeyboardDictationAttemptIdentity
    ) -> Bool {
        guard let intent = try? dependencies.loadConsumedHandoffIntent() else {
            return false
        }
        return intent.requestID == identity.requestID
    }

    private func owns(_ state: KeyboardDictationStateRecord) -> Bool {
        activeDictationOwnership?.matches(state) == true
    }

    private func insertText(_ text: String) {
        guard insertionGate.beginEvent() else { return }
        defer { insertionGate.endEvent() }
        activeDocumentProxy.insertText(text)
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
        proxyHasText: Bool? = nil
    ) {
        dependencies.recordDiagnostic(
            .keyboardDelivery(
                stage,
                request: requestID.map(IOSDiagnosticCorrelationTag.init),
                claim: claimID.map(IOSDiagnosticCorrelationTag.init),
                proxyHasText: proxyHasText
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
