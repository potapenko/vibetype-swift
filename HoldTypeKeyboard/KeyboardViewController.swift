import UIKit

typealias KeyboardLatestExpiryScheduler = (
    Date,
    @escaping @MainActor () -> Void
) -> Timer?

typealias KeyboardContainingAppOpener = (
    URL,
    @escaping (Bool) -> Void
) -> Void

@MainActor
struct KeyboardViewControllerDependencies {
    let loadSnapshot: () throws -> KeyboardBridgeSnapshot?
    let loadDictationState: () throws -> KeyboardDictationStateRecord?
    let saveDictationCommand: (KeyboardDictationCommandRecord) throws -> Void
    let saveHandoffIntent: (KeyboardHandoffIntentRecord) throws -> Void
    let observeDictationState: (
        @escaping @MainActor () -> Void
    ) -> KeyboardDictationBridgeObserver?
    let now: () -> Date
    let makeRequestID: () -> UUID
    let documentProxyOverride: (any UITextDocumentProxy)?
    let inputModeSwitchKeyOverride: Bool?
    let fullAccessOverride: Bool?
    let scheduleLatestExpiry: KeyboardLatestExpiryScheduler
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
        documentProxyOverride: nil,
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
        openContainingAppOverride: nil,
        recordDiagnostic: { event in
            IOSRuntimeDiagnosticsStore.keyboard.record(event)
        }
    )
}

final class KeyboardViewController: UIInputViewController {
    private struct DictationRequestOwnership: Equatable {
        let requestID: UUID
        let extensionLifetimeID: UUID
        let hostContextGeneration: UInt64
    }

    let keyboardView = BrandStageKeyboardView()
    private let deleteRepeater = KeyboardDeleteRepeater()
    private var dependencies = KeyboardViewControllerDependencies.live
    private var lastDiagnosticState: IOSDiagnosticKeyboardState?
    private var cursorAccumulator = KeyboardCursorDragAccumulator()
    private var previousCursorLocationX: CGFloat?
    private var insertionGate = KeyboardInsertionEventGate()
    private var latestItem: KeyboardBridgeItem?
    private var dictationExpiryTimer: Timer?
    private var dictationObserver: KeyboardDictationBridgeObserver?
    private var dictationState: KeyboardDictationStateRecord?
    private var activeDictationRequestID: UUID?
    private var activeDictationOwnership: DictationRequestOwnership?
    private var insertedDictationRequestID: UUID?
    private var lastSeenDictationSessionID: UUID?
    private var pendingDictationCommand: KeyboardDictationCommandKind?
    private var pendingHandoffRequestID: UUID?
    private var handoffLaunchFailed = false
    private var forcesSessionNotRunning = false
    private var showsInputModeSwitchKey = true
    private var extensionLifetimeID = UUID()
    private var hostContextGeneration: UInt64 = 0
    private var automaticVoiceAction: KeyboardVoiceAction = .standard

    convenience init(dependencies: KeyboardViewControllerDependencies) {
        self.init(nibName: nil, bundle: nil)
        self.dependencies = dependencies
    }

    private var activeDocumentProxy: any UITextDocumentProxy {
        dependencies.documentProxyOverride ?? textDocumentProxy
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
        endExtensionLifetime()
        super.viewWillDisappear(animated)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        keyboardView.updatePreferredHeight(for: traitCollection)
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        invalidateHostContextOwnership()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
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
        keyboardView.onCancelRequested = { [weak self] in
            self?.sendDictationCommand(.cancel)
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
                cancelIsVisible: dictationPresentation.cancelIsVisible,
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
        voiceStage: KeyboardVoiceStagePresentation,
        cancelIsVisible: Bool
    ) {
        guard hasSharedContainerAccess else {
            recordKeyboardState(.noSharedAccess)
            return (
                .fullAccessRequired,
                .ready,
                false
            )
        }
        if pendingHandoffRequestID != nil {
            return (
                .openingHoldType,
                .opening,
                false
            )
        }
        guard !forcesSessionNotRunning, let dictationState else {
            return (
                handoffLaunchFailed ? .launchFailed : .ready,
                .ready,
                false
            )
        }
        if pendingDictationCommand == .start,
           activeDictationRequestID == dictationState.requestID {
            return (.starting, .starting, true)
        }
        if pendingDictationCommand == .finish,
           activeDictationRequestID == dictationState.requestID {
            return (.processing, .processing, true)
        }
        switch dictationState.phase {
        case .ready:
            return (.ready, .ready, false)
        case .listening
            where activeDictationRequestID != dictationState.requestID:
            return (
                .ready,
                .ready,
                false
            )
        case .listening:
            return (.listening, .listening, true)
        case .processing
            where activeDictationRequestID != dictationState.requestID:
            return (
                .ready,
                .ready,
                false
            )
        case .processing:
            return (.processing, .processing, true)
        case .resultReady, .unavailable:
            return (
                .ready,
                .ready,
                false
            )
        case .failed:
            return (
                .dictationFailed,
                .ready,
                false
            )
        }
    }

    private func reloadDictationState() {
        dictationExpiryTimer?.invalidate()
        dictationExpiryTimer = nil
        guard hasSharedContainerAccess else {
            dictationState = nil
            activeDictationRequestID = nil
            pendingDictationCommand = nil
            render()
            return
        }
        do {
            guard let state = try dependencies.loadDictationState(),
                  state.isValid(at: dependencies.now()) else {
                recordKeyboardState(.expired)
                dictationState = nil
                forcesSessionNotRunning = true
                render()
                return
            }
            if state.phase == .ready,
               state.requestID != lastSeenDictationSessionID {
                forcesSessionNotRunning = false
                lastSeenDictationSessionID = state.requestID
                insertedDictationRequestID = nil
                activeDictationRequestID = nil
                activeDictationOwnership = nil
            }
            if state.phase == .listening || state.phase == .processing {
                pendingDictationCommand = nil
            }
            dictationState = state
            recordKeyboardState(diagnosticState(for: state.phase))
            if state.phase == .resultReady,
               activeDictationRequestID == state.requestID,
               ownsCurrentHostContext(for: state.requestID),
               insertedDictationRequestID != state.requestID,
               let result = state.result {
                insertText(result)
                dependencies.recordDiagnostic(.keyboardInserted(.dictation))
                insertedDictationRequestID = state.requestID
                activeDictationRequestID = nil
                activeDictationOwnership = nil
                pendingDictationCommand = nil
                forcesSessionNotRunning = true
            } else if (state.phase == .unavailable || state.phase == .failed),
                      activeDictationRequestID == state.requestID {
                activeDictationRequestID = nil
                activeDictationOwnership = nil
                pendingDictationCommand = nil
                forcesSessionNotRunning = state.phase == .unavailable
            }
            dictationExpiryTimer = dependencies.scheduleLatestExpiry(
                state.expiresAt
            ) { [weak self] in
                guard let self,
                      self.dictationState?.requestID == state.requestID else {
                    return
                }
                self.dictationState = nil
                self.activeDictationRequestID = nil
                self.activeDictationOwnership = nil
                self.pendingDictationCommand = nil
                self.forcesSessionNotRunning = true
                self.recordKeyboardState(.expired)
                self.render()
            }
        } catch {
            recordKeyboardState(.failed)
            dictationState = nil
            forcesSessionNotRunning = true
        }
        render()
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
            beginDictation(action: automaticVoiceAction)
        case .listening:
            if activeDictationRequestID == state.requestID {
                sendDictationCommand(.finish)
            } else {
                beginHandoff()
            }
        case .processing:
            if activeDictationRequestID != state.requestID {
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
            sourceDocumentID: activeDocumentProxy.documentIdentifier,
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
              state.phase == .ready else {
            return
        }
        if action.translates, !state.translationAvailable {
            openTranslationSettings()
            return
        }
        activeDictationRequestID = state.requestID
        activeDictationOwnership = DictationRequestOwnership(
            requestID: state.requestID,
            extensionLifetimeID: extensionLifetimeID,
            hostContextGeneration: hostContextGeneration
        )
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
            extensionContext?.open(url, completionHandler: completion)
        }
    }

    private func sendDictationCommand(
        _ kind: KeyboardDictationCommandKind,
        action: KeyboardVoiceAction = .standard
    ) {
        guard hasSharedContainerAccess,
              let state = dictationState,
              state.expiresAt > dependencies.now(),
              (activeDictationRequestID == state.requestID
                || kind == .start) else {
            return
        }
        let now = dependencies.now()
        guard let command = KeyboardDictationCommandRecord(
            requestID: state.requestID,
            kind: kind,
            action: action,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(
                KeyboardDictationBridgeConfiguration.commandLifetime
            )
        ) else {
            return
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
            pendingDictationCommand = kind
            if kind == .cancel {
                activeDictationRequestID = nil
                activeDictationOwnership = nil
                pendingDictationCommand = nil
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
            activeDictationRequestID = nil
            activeDictationOwnership = nil
            forcesSessionNotRunning = true
        }
        render()
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
        extensionLifetimeID = UUID()
        hostContextGeneration &+= 1
        activeDictationRequestID = nil
        activeDictationOwnership = nil
        pendingDictationCommand = nil
        pendingHandoffRequestID = nil
        handoffLaunchFailed = false
        automaticVoiceAction = .standard
    }

    private func endExtensionLifetime() {
        hostContextGeneration &+= 1
        activeDictationRequestID = nil
        activeDictationOwnership = nil
        pendingDictationCommand = nil
        pendingHandoffRequestID = nil
    }

    private func invalidateHostContextOwnership() {
        hostContextGeneration &+= 1
        activeDictationOwnership = nil
    }

    private func ownsCurrentHostContext(for requestID: UUID) -> Bool {
        activeDictationOwnership == DictationRequestOwnership(
            requestID: requestID,
            extensionLifetimeID: extensionLifetimeID,
            hostContextGeneration: hostContextGeneration
        )
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
