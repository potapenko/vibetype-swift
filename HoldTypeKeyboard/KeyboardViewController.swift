import UIKit

typealias KeyboardSettingsOpener = (
    URL,
    @escaping (Bool) -> Void
) -> Void

typealias KeyboardLatestExpiryScheduler = (
    Date,
    @escaping @MainActor () -> Void
) -> Timer?

@MainActor
struct KeyboardViewControllerDependencies {
    let loadSnapshot: () throws -> KeyboardBridgeSnapshot?
    let loadDictationState: () throws -> KeyboardDictationStateRecord?
    let saveDictationCommand: (KeyboardDictationCommandRecord) throws -> Void
    let observeDictationState: (
        @escaping @MainActor () -> Void
    ) -> KeyboardDictationBridgeObserver?
    let now: () -> Date
    let documentProxyOverride: (any UITextDocumentProxy)?
    let settingsOpener: KeyboardSettingsOpener?
    let inputModeSwitchKeyOverride: Bool?
    let fullAccessOverride: Bool?
    let scheduleStatusReset: (TimeInterval, DispatchWorkItem) -> Void
    let scheduleLatestExpiry: KeyboardLatestExpiryScheduler

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
        observeDictationState: { action in
            KeyboardDictationBridgeObserver(
                name: KeyboardDictationBridgeConfiguration.stateNotification,
                action: action
            )
        },
        now: { Date() },
        documentProxyOverride: nil,
        settingsOpener: nil,
        inputModeSwitchKeyOverride: nil,
        fullAccessOverride: nil,
        scheduleStatusReset: { duration, workItem in
            DispatchQueue.main.asyncAfter(
                deadline: .now() + duration,
                execute: workItem
            )
        },
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
    private var cursorAccumulator = KeyboardCursorDragAccumulator()
    private var previousCursorLocationX: CGFloat?
    private var insertionGate = KeyboardInsertionEventGate()
    private var latestItem: KeyboardBridgeItem?
    private var latestExpiryTimer: Timer?
    private var dictationExpiryTimer: Timer?
    private var dictationObserver: KeyboardDictationBridgeObserver?
    private var dictationState: KeyboardDictationStateRecord?
    private var activeDictationRequestID: UUID?
    private var activeDictationOwnership: DictationRequestOwnership?
    private var insertedDictationRequestID: UUID?
    private var lastSeenDictationSessionID: UUID?
    private var pendingDictationCommand: KeyboardDictationCommandKind?
    private var forcesOpenHoldType = false
    private var statusResetWorkItem: DispatchWorkItem?
    private var activeStatusOverride: KeyboardTopRailStatus?
    private var settingsRequestID: UUID?
    private var showsInputModeSwitchKey = true
    private var extensionLifetimeID = UUID()
    private var hostContextGeneration: UInt64 = 0

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
        hasDictationKey = false
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
        beginExtensionLifetime()
        showsInputModeSwitchKey = shouldShowInputModeSwitchKey
        reloadSharedSnapshot()
        reloadDictationState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        deleteRepeater.stop()
        latestExpiryTimer?.invalidate()
        latestExpiryTimer = nil
        dictationExpiryTimer?.invalidate()
        dictationExpiryTimer = nil
        statusResetWorkItem?.cancel()
        activeStatusOverride = nil
        settingsRequestID = nil
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
        statusResetWorkItem?.cancel()
        activeStatusOverride = nil
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
        keyboardView.onSettingsRequested = { [weak self] in
            self?.openSettings()
        }
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
        keyboardView.onPunctuationRequested = { [weak self] character in
            self?.insertText(character)
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

            let now = dependencies.now()
            setLatestItem(
                snapshot.latestForInsertion(at: now),
                now: now
            )
        } catch {
            setLatestItem(nil)
        }
        render()
    }

    private func render() {
        let dictationPresentation = currentDictationPresentation
        keyboardView.render(
            BrandStageKeyboardPresentation(
                status: activeStatusOverride ?? dictationPresentation.status,
                latestIsEnabled: latestItem != nil,
                microphoneIsEnabled:
                    dictationPresentation.microphoneIsEnabled,
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
        status: KeyboardTopRailStatus,
        microphoneIsEnabled: Bool,
        cancelIsVisible: Bool
    ) {
        guard hasSharedContainerAccess else {
            return (.enableFullAccess, false, false)
        }
        guard !forcesOpenHoldType, let dictationState else {
            return (.openHoldType, false, false)
        }
        if pendingDictationCommand == .start {
            return (.ready, false, true)
        }
        if pendingDictationCommand == .finish {
            return (.processing, false, true)
        }
        switch dictationState.phase {
        case .ready:
            return (.ready, true, false)
        case .listening
            where activeDictationRequestID != dictationState.requestID:
            return (.openHoldType, false, false)
        case .listening:
            return (.listening, true, true)
        case .processing
            where activeDictationRequestID != dictationState.requestID:
            return (.openHoldType, false, false)
        case .processing:
            return (.processing, false, true)
        case .resultReady, .unavailable:
            return (.openHoldType, false, false)
        case .failed:
            return (.tryAgain, false, false)
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
                dictationState = nil
                forcesOpenHoldType = true
                render()
                return
            }
            if state.phase == .ready,
               state.requestID != lastSeenDictationSessionID {
                forcesOpenHoldType = false
                lastSeenDictationSessionID = state.requestID
                insertedDictationRequestID = nil
                activeDictationRequestID = nil
                activeDictationOwnership = nil
            }
            if state.phase == .listening || state.phase == .processing {
                pendingDictationCommand = nil
            }
            dictationState = state
            if state.phase == .resultReady,
               activeDictationRequestID == state.requestID,
               ownsCurrentHostContext(for: state.requestID),
               insertedDictationRequestID != state.requestID,
               let result = state.result {
                insertText(result)
                insertedDictationRequestID = state.requestID
                activeDictationRequestID = nil
                activeDictationOwnership = nil
                pendingDictationCommand = nil
                forcesOpenHoldType = true
            } else if (state.phase == .unavailable || state.phase == .failed),
                      activeDictationRequestID == state.requestID {
                activeDictationRequestID = nil
                activeDictationOwnership = nil
                pendingDictationCommand = nil
                forcesOpenHoldType = true
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
                self.forcesOpenHoldType = true
                self.render()
            }
        } catch {
            dictationState = nil
            forcesOpenHoldType = true
        }
        render()
    }

    private func handleMicrophoneCommand() {
        guard let state = dictationState else { return }
        switch state.phase {
        case .ready:
            activeDictationRequestID = state.requestID
            activeDictationOwnership = DictationRequestOwnership(
                requestID: state.requestID,
                extensionLifetimeID: extensionLifetimeID,
                hostContextGeneration: hostContextGeneration
            )
            sendDictationCommand(.start)
        case .listening:
            sendDictationCommand(.finish)
        case .processing, .resultReady, .unavailable, .failed:
            break
        }
    }

    private func sendDictationCommand(_ kind: KeyboardDictationCommandKind) {
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
            issuedAt: now,
            expiresAt: now.addingTimeInterval(
                KeyboardDictationBridgeConfiguration.commandLifetime
            )
        ) else {
            return
        }
        do {
            try dependencies.saveDictationCommand(command)
            pendingDictationCommand = kind
            if kind == .cancel {
                activeDictationRequestID = nil
                activeDictationOwnership = nil
                pendingDictationCommand = nil
                forcesOpenHoldType = true
            }
        } catch {
            pendingDictationCommand = nil
            activeDictationRequestID = nil
            activeDictationOwnership = nil
            forcesOpenHoldType = true
        }
        render()
    }

    private var returnIsEnabled: Bool {
        !((activeDocumentProxy.enablesReturnKeyAutomatically ?? false)
            && !activeDocumentProxy.hasText)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            showTemporaryStatus(.openSettings, duration: 1.6)
            return
        }
        let requestID = UUID()
        settingsRequestID = requestID
        statusResetWorkItem?.cancel()
        activeStatusOverride = nil
        render()
        let requested = requestSettingsOpen(url) { [weak self] opened in
            Task { @MainActor [weak self] in
                guard let self,
                      self.settingsRequestID == requestID else {
                    return
                }
                self.settingsRequestID = nil
                guard !opened else { return }
                self.showTemporaryStatus(
                    .openSettings,
                    duration: 1.6
                )
            }
        }
        guard requested else {
            settingsRequestID = nil
            showTemporaryStatus(.openSettings, duration: 1.6)
            return
        }
    }

    private func requestSettingsOpen(
        _ url: URL,
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        if let settingsOpener = dependencies.settingsOpener {
            settingsOpener(url, completion)
            return true
        }

        guard let extensionContext else {
            return false
        }
        extensionContext.open(url) { opened in
            completion(opened)
        }
        return true
    }

    private func insert(_ item: KeyboardBridgeItem) {
        guard item.expiresAt > dependencies.now() else {
            setLatestItem(nil)
            render()
            return
        }
        insertText(item.text)
    }

    private func beginExtensionLifetime() {
        extensionLifetimeID = UUID()
        hostContextGeneration &+= 1
        activeDictationRequestID = nil
        activeDictationOwnership = nil
        pendingDictationCommand = nil
    }

    private func endExtensionLifetime() {
        hostContextGeneration &+= 1
        activeDictationRequestID = nil
        activeDictationOwnership = nil
        pendingDictationCommand = nil
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

    private func showTemporaryStatus(
        _ status: KeyboardTopRailStatus,
        duration: TimeInterval
    ) {
        statusResetWorkItem?.cancel()
        activeStatusOverride = status
        render()
        let workItem = DispatchWorkItem { [weak self] in
            self?.activeStatusOverride = nil
            self?.reloadSharedSnapshot()
        }
        statusResetWorkItem = workItem
        dependencies.scheduleStatusReset(duration, workItem)
    }

    private func setLatestItem(
        _ item: KeyboardBridgeItem?,
        now: Date? = nil
    ) {
        let currentDate = now ?? dependencies.now()
        latestExpiryTimer?.invalidate()
        latestExpiryTimer = nil
        latestItem = item

        guard let item, item.expiresAt > currentDate else {
            latestItem = nil
            return
        }

        latestExpiryTimer = dependencies.scheduleLatestExpiry(
            item.expiresAt
        ) { [weak self] in
            guard let self, self.latestItem == item else { return }
            self.latestExpiryTimer = nil
            self.latestItem = nil
            self.render()
        }
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
