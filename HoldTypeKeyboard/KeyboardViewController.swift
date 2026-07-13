import UIKit

final class KeyboardViewController: UIInputViewController {
    private let keyboardView = BrandStageKeyboardView()
    private let deleteRepeater = KeyboardDeleteRepeater()
    private var cursorAccumulator = KeyboardCursorDragAccumulator()
    private var previousCursorLocationX: CGFloat?
    private var insertionGate = KeyboardInsertionEventGate()
    private var latestItem: KeyboardBridgeItem?
    private var latestExpiryTimer: Timer?
    private var statusResetWorkItem: DispatchWorkItem?
    private var activeStatusOverride: KeyboardTopRailStatus?
    private var historyRequestID: UUID?
    private var showsInputModeSwitchKey = true

    override func viewDidLoad() {
        super.viewDidLoad()
        hasDictationKey = false
        configureKeyboardView()
        reloadSharedSnapshot()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        showsInputModeSwitchKey = needsInputModeSwitchKey
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
        showsInputModeSwitchKey = needsInputModeSwitchKey
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
            self?.textDocumentProxy.adjustTextPosition(
                byCharacterOffset: offset
            )
        }
        keyboardView.onDeleteStarted = { [weak self] in
            guard let self else { return }
            deleteRepeater.start { [weak self] in
                self?.textDocumentProxy.deleteBackward()
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
            let store = try KeyboardBridgeStore.appGroup()
            guard let snapshot = try store.load() else {
                setLatestItem(nil)
                render()
                return
            }

            let now = Date()
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
                        for: textDocumentProxy.returnKeyType ?? .default
                    )
                ),
                returnIsEnabled: returnIsEnabled,
                showsInputModeSwitchKey: showsInputModeSwitchKey
            )
        )
    }

    private var returnIsEnabled: Bool {
        !((textDocumentProxy.enablesReturnKeyAutomatically ?? false)
            && !textDocumentProxy.hasText)
    }

    private func openHistory() {
        guard let url = HoldTypeContainingAppRoute.history.url,
              let extensionContext else {
            showTemporaryStatus(.openFailed, duration: 1.6)
            return
        }

        let requestID = UUID()
        historyRequestID = requestID
        statusResetWorkItem?.cancel()
        activeStatusOverride = nil
        render()
        extensionContext.open(url) { [weak self] opened in
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
    }

    private func insert(_ item: KeyboardBridgeItem) {
        guard item.expiresAt > Date() else {
            setLatestItem(nil)
            render()
            return
        }
        insertText(item.text)
    }

    private func insertText(_ text: String) {
        guard insertionGate.beginEvent() else { return }
        defer { insertionGate.endEvent() }
        textDocumentProxy.insertText(text)
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
        DispatchQueue.main.asyncAfter(
            deadline: .now() + duration,
            execute: workItem
        )
    }

    private func setLatestItem(
        _ item: KeyboardBridgeItem?,
        now: Date = Date()
    ) {
        latestExpiryTimer?.invalidate()
        latestExpiryTimer = nil
        latestItem = item

        guard let item, item.expiresAt > now else {
            latestItem = nil
            return
        }

        let timer = Timer(
            fire: item.expiresAt,
            interval: 0,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.latestItem == item else { return }
                self.latestExpiryTimer = nil
                self.latestItem = nil
                self.render()
            }
        }
        latestExpiryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
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
                textDocumentProxy.adjustTextPosition(
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
