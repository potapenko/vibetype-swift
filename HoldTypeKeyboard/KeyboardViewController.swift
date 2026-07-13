import UIKit

typealias KeyboardHistoryOpener = (
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
    let now: () -> Date
    let documentProxyOverride: (any UITextDocumentProxy)?
    let historyOpener: KeyboardHistoryOpener?
    let inputModeSwitchKeyOverride: Bool?
    let scheduleStatusReset: (TimeInterval, DispatchWorkItem) -> Void
    let scheduleLatestExpiry: KeyboardLatestExpiryScheduler

    static let live = KeyboardViewControllerDependencies(
        loadSnapshot: {
            let store = try KeyboardBridgeStore.appGroup()
            return try store.load()
        },
        now: { Date() },
        documentProxyOverride: nil,
        historyOpener: nil,
        inputModeSwitchKeyOverride: nil,
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
    let keyboardView = BrandStageKeyboardView()
    private let deleteRepeater = KeyboardDeleteRepeater()
    private var dependencies = KeyboardViewControllerDependencies.live
    private var cursorAccumulator = KeyboardCursorDragAccumulator()
    private var previousCursorLocationX: CGFloat?
    private var insertionGate = KeyboardInsertionEventGate()
    private var latestItem: KeyboardBridgeItem?
    private var latestExpiryTimer: Timer?
    private var statusResetWorkItem: DispatchWorkItem?
    private var activeStatusOverride: KeyboardTopRailStatus?
    private var historyRequestID: UUID?
    private var showsInputModeSwitchKey = true

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

    override func viewDidLoad() {
        super.viewDidLoad()
        hasDictationKey = false
        showsInputModeSwitchKey = shouldShowInputModeSwitchKey
        configureKeyboardView()
        reloadSharedSnapshot()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        showsInputModeSwitchKey = shouldShowInputModeSwitchKey
        reloadSharedSnapshot()
    }

    override func viewWillDisappear(_ animated: Bool) {
        deleteRepeater.stop()
        latestExpiryTimer?.invalidate()
        latestExpiryTimer = nil
        statusResetWorkItem?.cancel()
        activeStatusOverride = nil
        historyRequestID = nil
        super.viewWillDisappear(animated)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        keyboardView.updatePreferredHeight(for: traitCollection)
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        statusResetWorkItem?.cancel()
        activeStatusOverride = nil
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        showsInputModeSwitchKey = shouldShowInputModeSwitchKey
        reloadSharedSnapshot()
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
            guard let self, let latestItem else { return }
            insert(latestItem)
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
        keyboardView.render(
            BrandStageKeyboardPresentation(
                status: activeStatusOverride ?? .ready,
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

    private var returnIsEnabled: Bool {
        !((activeDocumentProxy.enablesReturnKeyAutomatically ?? false)
            && !activeDocumentProxy.hasText)
    }

    private func openHistory() {
        guard let url = HoldTypeContainingAppRoute.history.url else {
            showTemporaryStatus(.openFailed, duration: 1.6)
            return
        }

        let requestID = UUID()
        historyRequestID = requestID
        statusResetWorkItem?.cancel()
        activeStatusOverride = nil
        render()
        let requested = requestHistoryOpen(url) { [weak self] opened in
            Task { @MainActor [weak self] in
                guard let self,
                      self.historyRequestID == requestID else {
                    return
                }
                self.historyRequestID = nil
                guard !opened else { return }
                self.showTemporaryStatus(
                    .openFailed,
                    duration: 1.6
                )
            }
        }
        guard requested else {
            historyRequestID = nil
            showTemporaryStatus(.openFailed, duration: 1.6)
            return
        }
    }

    private func requestHistoryOpen(
        _ url: URL,
        completion: @escaping (Bool) -> Void
    ) -> Bool {
        if let historyOpener = dependencies.historyOpener {
            historyOpener(url, completion)
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
