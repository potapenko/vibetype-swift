import UIKit

struct BrandStageKeyboardPresentation: Equatable {
    let status: KeyboardVoiceStatus
    let voiceStage: KeyboardVoiceStagePresentation
    let automaticVoiceAction: KeyboardVoiceAction
    let latestIsEnabled: Bool
    let cancelIsVisible: Bool
    let returnKey: KeyboardReturnKeyPresentation
    let returnIsEnabled: Bool
    let showsInputModeSwitchKey: Bool
}

private extension KeyboardVoiceStagePresentation {
    var keepsVoiceWorkspaceVisible: Bool {
        switch self {
        case .opening, .starting, .listening, .processing:
            true
        case .ready:
            false
        }
    }
}

/// The selected Brand Stage Adaptive composition. The controller owns document
/// proxy behavior; this view owns only layout, appearance, and touch routing.
final class BrandStageKeyboardView: UIView {
    var onLatestRequested: (() -> Void)?
    var onMicrophoneRequested: (() -> Void)?
    var onCancelRequested: (() -> Void)?
    var onQuickInsertRequested: ((String) -> Void)?
    var onAutomaticVoiceActionChanged: ((KeyboardVoiceAction) -> Void)?
    var onSpaceRequested: (() -> Void)?
    var onSpaceCursorGesture: ((UIGestureRecognizer.State, CGFloat) -> Void)?
    var onCursorStepRequested: ((Int) -> Void)?
    var onDeleteStarted: (() -> Void)?
    var onDeleteStopped: (() -> Void)?
    var onReturnRequested: (() -> Void)?

    let nextKeyboardButton = UIButton(type: .system)

    private let rootStack = UIStackView()
    private let bodyStack = UIStackView()
    private let commandStack = UIStackView()
    private let quickInsertButton = UIButton(type: .system)
    private let autoButton = UIButton(type: .system)
    private let automaticModesDismissControl = UIControl()
    private let automaticModesPanel = KeyboardAutomaticModesPanelView()
    private let topLeadingContainer = UIView()
    private let latestButton = UIButton(type: .system)
    private let logoImageView = UIImageView()
    private let stageContainer = UIView()
    private let voiceStage = UIView()
    private let quickInsertStage = UIStackView()
    private let quickInsertPunctuationScrollView = UIScrollView()
    private let quickInsertEmojiPrimaryScrollView = UIScrollView()
    private let quickInsertEmojiSecondaryScrollView = UIScrollView()
    private let quickInsertEmojiCompactScrollView = UIScrollView()
    private let editingRow = UIStackView()
    private let spaceButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let returnButton = UIButton(type: .system)
    private let microphoneView = UIButton(type: .system)
    private let voiceActivityIndicator = KeyboardVoiceActivityIndicatorView()
    private let cancelButton = UIButton(type: .system)
    private var microphoneWidthConstraint: NSLayoutConstraint?
    private var microphoneHeightConstraint: NSLayoutConstraint?
    private var stageMinimumHeightConstraint: NSLayoutConstraint?
    private var preferredHeightConstraint: NSLayoutConstraint?
    private var logoWidthConstraint: NSLayoutConstraint?
    private var logoHeightConstraint: NSLayoutConstraint?
    private var rootTopConstraint: NSLayoutConstraint?
    private var rootBottomConstraint: NSLayoutConstraint?
    private var compactLayoutConstraints: [NSLayoutConstraint] = []
    private var usesCompactPhoneLayout: Bool?
    private var editingRowWithGlobeConstraints: [NSLayoutConstraint] = []
    private var editingRowWithoutGlobeConstraints: [NSLayoutConstraint] = []
    private var showsGlobeInEditingRow: Bool?
    private var quickInsertButtons: [UIButton] = []
    private var reduceTransparencyObserver: NSObjectProtocol?
    private var renderedStatus: KeyboardVoiceStatus?
    private var renderedVoiceStage: KeyboardVoiceStagePresentation = .ready
    private var renderedAutomaticVoiceAction: KeyboardVoiceAction = .standard
    private var quickInsertIsPresented = false
    private var automaticModesArePresented = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
        configureInteractions()
        applyAppearance()
        registerForTraitChanges([
            UITraitUserInterfaceStyle.self,
            UITraitVerticalSizeClass.self,
            UITraitAccessibilityContrast.self,
            UITraitPreferredContentSizeCategory.self,
        ]) { (view: BrandStageKeyboardView, _) in
            view.applyAppearance()
            view.updatePreferredHeight(for: view.traitCollection)
        }
        reduceTransparencyObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyAppearance()
            }
        }
    }

    isolated deinit {
        if let reduceTransparencyObserver {
            NotificationCenter.default.removeObserver(
                reduceTransparencyObserver
            )
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updatePreferredHeight(for: traitCollection)
    }

    func render(_ presentation: BrandStageKeyboardPresentation) {
        renderedVoiceStage = presentation.voiceStage
        renderedAutomaticVoiceAction = presentation.automaticVoiceAction
        if presentation.voiceStage.keepsVoiceWorkspaceVisible {
            quickInsertIsPresented = false
            automaticModesArePresented = false
        }
        quickInsertButton.isEnabled = !presentation.voiceStage
            .keepsVoiceWorkspaceVisible
        autoButton.isEnabled = !presentation.voiceStage
            .keepsVoiceWorkspaceVisible
        latestButton.isEnabled = presentation.latestIsEnabled
        renderVoiceStage(
            presentation.voiceStage,
            cancelIsVisible: presentation.cancelIsVisible
        )
        updateInputModeSwitchKeyVisibility(
            presentation.showsInputModeSwitchKey
        )
        returnButton.isEnabled = presentation.returnIsEnabled
        renderReturnKey(presentation.returnKey)

        if renderedStatus != presentation.status,
           let announcement = presentation.status.accessibilityAnnouncement {
            UIAccessibility.post(
                notification: .announcement,
                argument: announcement
            )
        }
        renderedStatus = presentation.status
        updateWorkspaceVisibility()
        updateQuickInsertButtonPresentation()
        updateAutoButtonPresentation()
        updateAutomaticModesVisibility()
    }

    private func renderVoiceStage(
        _ presentation: KeyboardVoiceStagePresentation,
        cancelIsVisible: Bool
    ) {
        microphoneView.isEnabled = false
        microphoneView.accessibilityValue = nil
        cancelButton.isHidden = true
        cancelButton.isEnabled = false
        switch presentation {
        case .ready:
            microphoneView.isEnabled = true
            voiceActivityIndicator.render(.ready)
            microphoneView.accessibilityLabel = "Start keyboard dictation"
            microphoneView.accessibilityValue = "Ready"
        case .opening:
            voiceActivityIndicator.render(.ready)
            microphoneView.accessibilityLabel = "Opening HoldType"
            microphoneView.accessibilityValue = "Please wait"
        case .listening:
            microphoneView.isEnabled = true
            voiceActivityIndicator.render(.listening)
            microphoneView.accessibilityLabel = "Finish keyboard dictation"
            microphoneView.accessibilityValue = "Listening"
            cancelButton.isHidden = !cancelIsVisible
            cancelButton.isEnabled = cancelIsVisible
        case .starting:
            voiceActivityIndicator.render(.ready)
            microphoneView.accessibilityLabel = "Starting keyboard dictation"
            microphoneView.accessibilityValue = "Starting"
            cancelButton.isHidden = !cancelIsVisible
            cancelButton.isEnabled = cancelIsVisible
        case .processing:
            voiceActivityIndicator.render(.recognizing)
            microphoneView.accessibilityLabel = "Processing keyboard dictation"
            microphoneView.accessibilityValue = "Recognizing"
            cancelButton.isHidden = !cancelIsVisible
            cancelButton.isEnabled = cancelIsVisible
        }
    }

    private func updateWorkspaceVisibility() {
        quickInsertStage.isHidden = !quickInsertIsPresented
        voiceStage.isHidden = quickInsertIsPresented
        logoImageView.isHidden = true

        stageContainer.accessibilityValue = quickInsertIsPresented
            ? "Quick Insert"
            : renderedStatus?.rawValue
    }

    func updatePreferredHeight(for traitCollection: UITraitCollection) {
        let isCompactPhone = traitCollection.userInterfaceIdiom == .phone
            && traitCollection.verticalSizeClass == .compact
        updateAdaptiveLayout(isCompactPhone: isCompactPhone)
        let baseHeight: CGFloat
        if isCompactPhone {
            baseHeight = 176 + safeAreaInsets.bottom
        } else if bounds.width > 0, bounds.width < 600 {
            baseHeight = 302
        } else {
            baseHeight = 284
        }

        let safeWidth = bounds.width
            - safeAreaInsets.left
            - safeAreaInsets.right
        let fittingWidth = min(max(safeWidth - 32, 280), 760)
        let contentSize = rootStack.systemLayoutSizeFitting(
            CGSize(
                width: fittingWidth,
                height: UIView.layoutFittingCompressedSize.height
            ),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let verticalInsets: CGFloat = isCompactPhone
            ? 16 + safeAreaInsets.bottom
            : 28
        let resolvedHeight = max(
            baseHeight,
            ceil(contentSize.height + verticalInsets)
        )
        if preferredHeightConstraint?.constant != resolvedHeight {
            preferredHeightConstraint?.constant = resolvedHeight
        }
    }

    private func updateAdaptiveLayout(isCompactPhone: Bool) {
        guard usesCompactPhoneLayout != isCompactPhone else { return }
        NSLayoutConstraint.deactivate(compactLayoutConstraints)

        rootStack.spacing = isCompactPhone ? 8 : 10
        bodyStack.axis = isCompactPhone ? .horizontal : .vertical
        bodyStack.spacing = isCompactPhone ? 8 : 10
        commandStack.spacing = isCompactPhone ? 8 : 10
        quickInsertStage.spacing = isCompactPhone ? 6 : 8
        quickInsertEmojiPrimaryScrollView.isHidden = isCompactPhone
        quickInsertEmojiSecondaryScrollView.isHidden = isCompactPhone
        quickInsertEmojiCompactScrollView.isHidden = !isCompactPhone
        logoWidthConstraint?.constant = isCompactPhone ? 28 : 34
        logoHeightConstraint?.constant = isCompactPhone ? 28 : 34
        microphoneWidthConstraint?.constant = isCompactPhone ? 88 : 128
        microphoneHeightConstraint?.constant = isCompactPhone ? 88 : 128
        stageMinimumHeightConstraint?.constant = isCompactPhone ? 96 : 128
        rootTopConstraint?.constant = isCompactPhone ? 8 : 10
        rootBottomConstraint?.constant = isCompactPhone ? -8 : -16

        if isCompactPhone {
            NSLayoutConstraint.activate(compactLayoutConstraints)
        }
        usesCompactPhoneLayout = isCompactPhone
    }

    private func updateInputModeSwitchKeyVisibility(_ showsGlobe: Bool) {
        guard showsGlobeInEditingRow != showsGlobe else { return }
        NSLayoutConstraint.deactivate(editingRowWithGlobeConstraints)
        NSLayoutConstraint.deactivate(editingRowWithoutGlobeConstraints)
        nextKeyboardButton.isHidden = !showsGlobe
        NSLayoutConstraint.activate(
            showsGlobe
                ? editingRowWithGlobeConstraints
                : editingRowWithoutGlobeConstraints
        )
        showsGlobeInEditingRow = showsGlobe
    }

    private func configureHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Self.keyboardBackground
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.maskedCorners = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner,
        ]
        layer.masksToBounds = true

        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.axis = .vertical
        rootStack.spacing = 10
        addSubview(rootStack)

        let topRail = makeTopRail()
        configureVoiceStage()
        configureQuickInsertStage()
        stageContainer.translatesAutoresizingMaskIntoConstraints = false
        stageContainer.accessibilityIdentifier = "keyboard.brand-stage.stage"
        let stageViews = [
            voiceStage,
            quickInsertStage,
        ]
        for stageView in stageViews {
            stageContainer.addSubview(stageView)
        }
        let stageMinimumHeight = stageContainer.heightAnchor.constraint(
            greaterThanOrEqualToConstant: 128
        )
        stageMinimumHeightConstraint = stageMinimumHeight
        var stageConstraints: [NSLayoutConstraint] = [stageMinimumHeight]
        for stageView in stageViews {
            let fillsAvailableWidth = stageView.widthAnchor.constraint(
                equalTo: stageContainer.widthAnchor
            )
            fillsAvailableWidth.priority = UILayoutPriority(999)
            let prefersMaximumWidth = stageView.widthAnchor.constraint(
                equalToConstant: 520
            )
            prefersMaximumWidth.priority = UILayoutPriority(998)
            stageConstraints.append(contentsOf: [
                stageView.leadingAnchor.constraint(
                    greaterThanOrEqualTo: stageContainer.leadingAnchor
                ),
                stageView.trailingAnchor.constraint(
                    lessThanOrEqualTo: stageContainer.trailingAnchor
                ),
                stageView.centerXAnchor.constraint(
                    equalTo: stageContainer.centerXAnchor
                ),
                stageView.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
                fillsAvailableWidth,
                prefersMaximumWidth,
                stageView.topAnchor.constraint(equalTo: stageContainer.topAnchor),
                stageView.bottomAnchor.constraint(equalTo: stageContainer.bottomAnchor),
            ])
        }
        NSLayoutConstraint.activate(stageConstraints)

        let editingRow = makeEditingRow()
        commandStack.axis = .vertical
        commandStack.alignment = .fill
        commandStack.distribution = .fill
        commandStack.spacing = 10
        commandStack.addArrangedSubview(editingRow)

        bodyStack.axis = .vertical
        bodyStack.alignment = .fill
        bodyStack.distribution = .fill
        bodyStack.spacing = 10
        bodyStack.addArrangedSubview(stageContainer)
        bodyStack.addArrangedSubview(commandStack)

        rootStack.addArrangedSubview(topRail)
        rootStack.addArrangedSubview(bodyStack)
        configureAutomaticModesOverlay()

        let height = heightAnchor.constraint(equalToConstant: 302)
        height.priority = UILayoutPriority(999)
        preferredHeightConstraint = height
        let fillsAvailableWidth = rootStack.widthAnchor.constraint(
            equalTo: safeAreaLayoutGuide.widthAnchor,
            constant: -32
        )
        fillsAvailableWidth.priority = UILayoutPriority(999)
        let prefersMaximumWidth = rootStack.widthAnchor.constraint(
            equalToConstant: 760
        )
        prefersMaximumWidth.priority = UILayoutPriority(998)

        let rootTop = rootStack.topAnchor.constraint(
            equalTo: topAnchor,
            constant: 10
        )
        rootTopConstraint = rootTop
        let rootBottom = rootStack.bottomAnchor.constraint(
            equalTo: safeAreaLayoutGuide.bottomAnchor,
            constant: -16
        )
        rootBottomConstraint = rootBottom
        let compactStageWidth = stageContainer.widthAnchor.constraint(
            equalToConstant: 300
        )
        compactStageWidth.priority = UILayoutPriority(999)
        let compactSpaceMinimumWidth = spaceButton.widthAnchor.constraint(
            greaterThanOrEqualToConstant: 120
        )
        compactSpaceMinimumWidth.priority = UILayoutPriority(999)
        compactLayoutConstraints = [
            stageContainer.widthAnchor.constraint(
                greaterThanOrEqualToConstant: 296
            ),
            compactStageWidth,
            commandStack.widthAnchor.constraint(
                greaterThanOrEqualToConstant: 320
            ),
            compactSpaceMinimumWidth,
        ]

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor,
                constant: 16
            ),
            rootStack.trailingAnchor.constraint(
                lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -16
            ),
            rootStack.centerXAnchor.constraint(
                equalTo: safeAreaLayoutGuide.centerXAnchor
            ),
            rootStack.widthAnchor.constraint(lessThanOrEqualToConstant: 760),
            fillsAvailableWidth,
            prefersMaximumWidth,
            rootTop,
            rootBottom,
            height,
            topRail.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            editingRow.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    private func makeTopRail() -> UIView {
        configureUtilityKey(
            quickInsertButton,
            systemImage: "face.smiling",
            accessibilityLabel: "Open Quick Insert"
        )
        quickInsertButton.accessibilityIdentifier =
            "keyboard.brand-stage.quick-insert-toggle"

        configureTopAction(
            autoButton,
            title: "Auto",
            systemImage: "chevron.down",
            accessibilityLabel: "Automatic voice modes"
        )
        var autoConfiguration = autoButton.configuration
        autoConfiguration?.imagePlacement = .trailing
        autoButton.configuration = autoConfiguration
        autoButton.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        autoButton.setContentHuggingPriority(.required, for: .horizontal)
        autoButton.accessibilityIdentifier = "keyboard.brand-stage.auto"

        configureTopAction(
            latestButton,
            title: "Latest",
            systemImage: "arrow.down.doc",
            accessibilityLabel: "Insert latest"
        )
        latestButton.accessibilityIdentifier = "keyboard.brand-stage.latest"

        logoImageView.image = UIImage(named: "HoldTypeMark")
            ?? UIImage(systemName: "waveform.circle.fill")
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.image = logoImageView.image?.withRenderingMode(
            .alwaysOriginal
        )
        logoImageView.isAccessibilityElement = false
        logoImageView.accessibilityIdentifier = "keyboard.brand-stage.logo"
        let logoWidth = logoImageView.widthAnchor.constraint(
            equalToConstant: 34
        )
        let logoHeight = logoImageView.heightAnchor.constraint(
            equalToConstant: 34
        )
        logoWidthConstraint = logoWidth
        logoHeightConstraint = logoHeight
        NSLayoutConstraint.activate([
            logoWidth,
            logoHeight,
        ])

        let utilityStack = UIStackView(
            arrangedSubviews: [
                quickInsertButton,
                autoButton,
            ]
        )
        utilityStack.translatesAutoresizingMaskIntoConstraints = false
        utilityStack.axis = .horizontal
        utilityStack.alignment = .center
        utilityStack.distribution = .fill
        utilityStack.spacing = 4
        utilityStack.accessibilityIdentifier =
            "keyboard.brand-stage.utility-actions"
        topLeadingContainer.addSubview(utilityStack)
        NSLayoutConstraint.activate([
            utilityStack.leadingAnchor.constraint(
                equalTo: topLeadingContainer.leadingAnchor
            ),
            utilityStack.trailingAnchor.constraint(
                equalTo: topLeadingContainer.trailingAnchor
            ),
            utilityStack.centerYAnchor.constraint(
                equalTo: topLeadingContainer.centerYAnchor
            ),
            utilityStack.heightAnchor.constraint(equalToConstant: 44),
            quickInsertButton.widthAnchor.constraint(equalToConstant: 44),
            autoButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
            autoButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        let rail = UIView()
        rail.translatesAutoresizingMaskIntoConstraints = false
        rail.addSubview(topLeadingContainer)
        rail.addSubview(logoImageView)
        rail.addSubview(latestButton)
        topLeadingContainer.translatesAutoresizingMaskIntoConstraints = false
        latestButton.translatesAutoresizingMaskIntoConstraints = false
        latestButton.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        let centersLogo = logoImageView.centerXAnchor.constraint(
            equalTo: rail.centerXAnchor
        )
        centersLogo.priority = UILayoutPriority(998)
        NSLayoutConstraint.activate([
            topLeadingContainer.leadingAnchor.constraint(
                equalTo: rail.leadingAnchor
            ),
            topLeadingContainer.centerYAnchor.constraint(
                equalTo: rail.centerYAnchor
            ),
            topLeadingContainer.heightAnchor.constraint(equalToConstant: 44),
            logoImageView.centerYAnchor.constraint(equalTo: rail.centerYAnchor),
            centersLogo,
            topLeadingContainer.trailingAnchor.constraint(
                lessThanOrEqualTo: logoImageView.leadingAnchor,
                constant: -3
            ),
            latestButton.trailingAnchor.constraint(equalTo: rail.trailingAnchor),
            latestButton.centerYAnchor.constraint(equalTo: rail.centerYAnchor),
            latestButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: logoImageView.trailingAnchor,
                constant: 3
            ),
            latestButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            latestButton.heightAnchor.constraint(equalToConstant: 44),
            rail.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
        return rail
    }

    private func configureAutomaticModesOverlay() {
        automaticModesDismissControl.translatesAutoresizingMaskIntoConstraints =
            false
        automaticModesDismissControl.isAccessibilityElement = false
        automaticModesDismissControl.accessibilityIdentifier =
            "keyboard.brand-stage.auto-modes-dismiss"
        automaticModesDismissControl.isHidden = true
        automaticModesPanel.isHidden = true

        addSubview(automaticModesDismissControl)
        addSubview(automaticModesPanel)

        let preferredPanelWidth = automaticModesPanel.widthAnchor.constraint(
            equalToConstant: 280
        )
        preferredPanelWidth.priority = UILayoutPriority(999)
        let followsAutoLeading = automaticModesPanel.leadingAnchor.constraint(
            equalTo: autoButton.leadingAnchor
        )
        followsAutoLeading.priority = UILayoutPriority(999)
        let preferredPanelHeight = automaticModesPanel.heightAnchor.constraint(
            equalToConstant: 117
        )
        preferredPanelHeight.priority = UILayoutPriority(999)
        let followsAutoBottom = automaticModesPanel.topAnchor.constraint(
            equalTo: autoButton.bottomAnchor,
            constant: 6
        )
        followsAutoBottom.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            automaticModesDismissControl.leadingAnchor.constraint(
                equalTo: leadingAnchor
            ),
            automaticModesDismissControl.trailingAnchor.constraint(
                equalTo: trailingAnchor
            ),
            automaticModesDismissControl.topAnchor.constraint(equalTo: topAnchor),
            automaticModesDismissControl.bottomAnchor.constraint(
                equalTo: bottomAnchor
            ),
            automaticModesPanel.leadingAnchor.constraint(
                greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor,
                constant: 16
            ),
            automaticModesPanel.trailingAnchor.constraint(
                lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -16
            ),
            automaticModesPanel.bottomAnchor.constraint(
                lessThanOrEqualTo: bottomAnchor
            ),
            automaticModesPanel.widthAnchor.constraint(
                lessThanOrEqualToConstant: 280
            ),
            automaticModesPanel.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 117
            ),
            preferredPanelWidth,
            preferredPanelHeight,
            followsAutoLeading,
            followsAutoBottom,
        ])
    }

    private func configureVoiceStage() {
        voiceStage.translatesAutoresizingMaskIntoConstraints = false
        microphoneView.translatesAutoresizingMaskIntoConstraints = false
        voiceActivityIndicator.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        voiceStage.addSubview(microphoneView)
        voiceStage.addSubview(cancelButton)
        microphoneView.addSubview(voiceActivityIndicator)

        microphoneView.layer.masksToBounds = false
        microphoneView.isUserInteractionEnabled = true
        microphoneView.isAccessibilityElement = true
        microphoneView.accessibilityTraits.insert(.button)
        microphoneView.accessibilityIdentifier = "keyboard.brand-stage.voice"
        voiceActivityIndicator.accessibilityIdentifier =
            "keyboard.brand-stage.voice-indicator"
        let microphoneWidth = microphoneView.widthAnchor.constraint(
            equalToConstant: 128
        )
        let microphoneHeight = microphoneView.heightAnchor.constraint(
            equalToConstant: 128
        )
        microphoneWidthConstraint = microphoneWidth
        microphoneHeightConstraint = microphoneHeight
        NSLayoutConstraint.activate([
            microphoneView.centerXAnchor.constraint(
                equalTo: voiceStage.centerXAnchor
            ),
            microphoneView.centerYAnchor.constraint(
                equalTo: voiceStage.centerYAnchor
            ),
            microphoneWidth,
            microphoneHeight,
            voiceActivityIndicator.leadingAnchor.constraint(
                equalTo: microphoneView.leadingAnchor
            ),
            voiceActivityIndicator.trailingAnchor.constraint(
                equalTo: microphoneView.trailingAnchor
            ),
            voiceActivityIndicator.topAnchor.constraint(
                equalTo: microphoneView.topAnchor
            ),
            voiceActivityIndicator.bottomAnchor.constraint(
                equalTo: microphoneView.bottomAnchor
            ),
        ])

        var cancelConfiguration = UIButton.Configuration.bordered()
        cancelConfiguration.title = "Cancel"
        cancelConfiguration.cornerStyle = .medium
        cancelButton.configuration = cancelConfiguration
        cancelButton.isHidden = true
        cancelButton.accessibilityIdentifier =
            "keyboard.brand-stage.cancel"
        cancelButton.widthAnchor.constraint(equalToConstant: 72).isActive = true
        cancelButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        NSLayoutConstraint.activate([
            cancelButton.trailingAnchor.constraint(
                equalTo: voiceStage.trailingAnchor
            ),
            cancelButton.centerYAnchor.constraint(
                equalTo: voiceStage.centerYAnchor
            ),
        ])
    }

    private func configureQuickInsertStage() {
        quickInsertStage.translatesAutoresizingMaskIntoConstraints = false
        quickInsertStage.axis = .vertical
        quickInsertStage.alignment = .fill
        quickInsertStage.distribution = .fill
        quickInsertStage.spacing = 8
        quickInsertStage.accessibilityIdentifier =
            "keyboard.brand-stage.quick-insert"

        configureQuickInsertRow(
            quickInsertPunctuationScrollView,
            items: KeyboardQuickInsertCatalog.punctuation,
            category: "punctuation"
        )
        configureQuickInsertRow(
            quickInsertEmojiPrimaryScrollView,
            items: KeyboardQuickInsertCatalog.emojiPrimary,
            category: "emoji"
        )
        configureQuickInsertRow(
            quickInsertEmojiSecondaryScrollView,
            items: KeyboardQuickInsertCatalog.emojiSecondary,
            category: "emoji-secondary"
        )
        configureQuickInsertRow(
            quickInsertEmojiCompactScrollView,
            items: KeyboardQuickInsertCatalog.emoji,
            category: "emoji-compact"
        )
        quickInsertEmojiCompactScrollView.isHidden = true

        quickInsertStage.addArrangedSubview(quickInsertPunctuationScrollView)
        quickInsertStage.addArrangedSubview(
            quickInsertEmojiPrimaryScrollView
        )
        quickInsertStage.addArrangedSubview(
            quickInsertEmojiSecondaryScrollView
        )
        quickInsertStage.addArrangedSubview(
            quickInsertEmojiCompactScrollView
        )
        quickInsertStage.isHidden = true
    }

    private func configureQuickInsertRow(
        _ scrollView: UIScrollView,
        items: [KeyboardQuickInsertItem],
        category: String
    ) {
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.isDirectionalLockEnabled = true
        scrollView.clipsToBounds = true
        scrollView.accessibilityIdentifier =
            "keyboard.brand-stage.quick-insert.\(category)-row"
        scrollView.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .fill
        row.spacing = 6
        scrollView.addSubview(row)

        for item in items {
            let button = UIButton(type: .system)
            configureKey(
                button,
                title: item.text,
                accessibilityLabel: item.accessibilityLabel
            )
            button.accessibilityIdentifier =
                "keyboard.brand-stage.quick-insert.\(category).\(item.id)"
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            button.addAction(UIAction { [weak self] _ in
                self?.handleQuickInsertSelection(item.text)
            }, for: .touchUpInside)
            quickInsertButtons.append(button)
            row.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor
            ),
            row.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor
            ),
            row.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor
            ),
            row.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor
            ),
            row.heightAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.heightAnchor
            ),
        ])
    }

    private func makeEditingRow() -> UIStackView {
        configureKey(
            nextKeyboardButton,
            systemImage: "globe",
            accessibilityLabel: "Next keyboard"
        )
        configureKey(
            spaceButton,
            title: "space",
            accessibilityLabel: "Space"
        )
        spaceButton.accessibilityHint =
            "Tap for a space. Touch and drag to move the cursor."
        configureKey(
            deleteButton,
            systemImage: "delete.left",
            accessibilityLabel: "Delete"
        )
        configureKey(
            returnButton,
            systemImage: "return",
            accessibilityLabel: "Return"
        )
        nextKeyboardButton.accessibilityIdentifier =
            "keyboard.brand-stage.next-keyboard"
        spaceButton.accessibilityIdentifier = "keyboard.brand-stage.space"
        deleteButton.accessibilityIdentifier = "keyboard.brand-stage.delete"
        returnButton.accessibilityIdentifier = "keyboard.brand-stage.return"
        returnButton.titleLabel?.adjustsFontSizeToFitWidth = true
        returnButton.titleLabel?.minimumScaleFactor = 0.7
        returnButton.titleLabel?.numberOfLines = 1

        for button in [
            nextKeyboardButton,
            spaceButton,
            deleteButton,
            returnButton,
        ] {
            editingRow.addArrangedSubview(button)
        }
        editingRow.axis = .horizontal
        editingRow.distribution = .fill
        editingRow.spacing = 8

        editingRowWithGlobeConstraints = [
            spaceButton.widthAnchor.constraint(
                equalTo: nextKeyboardButton.widthAnchor,
                multiplier: 4.35
            ),
            deleteButton.widthAnchor.constraint(
                equalTo: nextKeyboardButton.widthAnchor,
                multiplier: 1.15
            ),
            returnButton.widthAnchor.constraint(
                equalTo: nextKeyboardButton.widthAnchor,
                multiplier: 1.25
            ),
        ]
        editingRowWithoutGlobeConstraints = [
            spaceButton.widthAnchor.constraint(
                equalTo: deleteButton.widthAnchor,
                multiplier: 3.8
            ),
            returnButton.widthAnchor.constraint(
                equalTo: deleteButton.widthAnchor,
                multiplier: 1.07
            ),
        ]
        for constraint in editingRowWithGlobeConstraints
            + editingRowWithoutGlobeConstraints {
            constraint.priority = .defaultHigh
        }
        let minimumEditingKeyWidths = [
            nextKeyboardButton.widthAnchor.constraint(
                greaterThanOrEqualToConstant: 44
            ),
            deleteButton.widthAnchor.constraint(
                greaterThanOrEqualToConstant: 44
            ),
            returnButton.widthAnchor.constraint(
                greaterThanOrEqualToConstant: 44
            ),
        ]
        for constraint in minimumEditingKeyWidths {
            // The Globe may become a hidden arranged subview when iOS supplies
            // its own input-mode switcher below the extension.
            constraint.priority = UILayoutPriority(999)
        }
        NSLayoutConstraint.activate(minimumEditingKeyWidths)
        updateInputModeSwitchKeyVisibility(true)
        return editingRow
    }

    private func configureInteractions() {
        quickInsertButton.addTarget(
            self,
            action: #selector(quickInsertToggled),
            for: .touchUpInside
        )
        autoButton.addTarget(
            self,
            action: #selector(autoToggled),
            for: .touchUpInside
        )
        automaticModesDismissControl.addTarget(
            self,
            action: #selector(automaticModesDismissed),
            for: .touchUpInside
        )
        automaticModesPanel.onTranslationToggleRequested = { [weak self] in
            self?.toggleAutomaticTranslation()
        }
        automaticModesPanel.onCorrectionToggleRequested = { [weak self] in
            self?.toggleAutomaticCorrection()
        }
        automaticModesPanel.onDismissRequested = { [weak self] in
            self?.dismissAutomaticModesPanel()
        }
        latestButton.addTarget(
            self,
            action: #selector(latestTapped),
            for: .touchUpInside
        )
        microphoneView.addTarget(
            self,
            action: #selector(microphoneTapped),
            for: .touchUpInside
        )
        cancelButton.addTarget(
            self,
            action: #selector(cancelTapped),
            for: .touchUpInside
        )
        spaceButton.addTarget(
            self,
            action: #selector(spaceTapped),
            for: .touchUpInside
        )
        let cursorGesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(spaceCursorGestureChanged(_:))
        )
        cursorGesture.minimumPressDuration = 0.30
        cursorGesture.cancelsTouchesInView = true
        spaceButton.addGestureRecognizer(cursorGesture)
        spaceButton.accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "Move cursor left",
                target: self,
                selector: #selector(moveCursorLeft)
            ),
            UIAccessibilityCustomAction(
                name: "Move cursor right",
                target: self,
                selector: #selector(moveCursorRight)
            ),
        ]

        deleteButton.addTarget(
            self,
            action: #selector(deleteStarted),
            for: .touchDown
        )
        for event: UIControl.Event in [
            .touchUpInside,
            .touchUpOutside,
            .touchCancel,
            .touchDragExit,
        ] {
            deleteButton.addTarget(
                self,
                action: #selector(deleteStopped),
                for: event
            )
        }
        returnButton.addTarget(
            self,
            action: #selector(returnTapped),
            for: .touchUpInside
        )
    }

    private func renderReturnKey(_ presentation: KeyboardReturnKeyPresentation) {
        var configuration = returnButton.configuration
        switch presentation {
        case .returnSymbol:
            configuration?.title = nil
            configuration?.image = UIImage(systemName: "return")
        case .title(let title):
            configuration?.title = title
            configuration?.image = nil
        }
        configuration?.titleLineBreakMode = .byClipping
        returnButton.configuration = configuration
        returnButton.accessibilityLabel = presentation.accessibilityLabel
    }

    private func configureKey(
        _ button: UIButton,
        title: String? = nil,
        systemImage: String? = nil,
        accessibilityLabel: String
    ) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = systemImage.flatMap(UIImage.init(systemName:))
        configuration.imagePadding = 6
        configuration.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: 8,
            bottom: 0,
            trailing: 8
        )
        configuration.baseBackgroundColor = Self.editingKeyBackground
        configuration.baseForegroundColor = Self.keyForeground
        configuration.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFontMetrics(forTextStyle: .body).scaledFont(
                    for: UIFont.systemFont(ofSize: 16, weight: .medium),
                    maximumPointSize: 20
                )
                return outgoing
            }
        button.configuration = configuration
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        button.layer.masksToBounds = false
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityTraits.insert(.keyboardKey)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            .isActive = true
    }

    private func configureTopAction(
        _ button: UIButton,
        title: String,
        systemImage: String,
        accessibilityLabel: String
    ) {
        configureKey(
            button,
            title: title,
            systemImage: systemImage,
            accessibilityLabel: accessibilityLabel
        )
        var configuration = button.configuration
        configuration?.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: 7,
            bottom: 0,
            trailing: 7
        )
        configuration?.imagePadding = 6
        configuration?.titleLineBreakMode = .byClipping
        configuration?.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        configuration?.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFontMetrics(forTextStyle: .subheadline)
                    .scaledFont(
                        for: UIFont.systemFont(ofSize: 15, weight: .medium),
                        maximumPointSize: 17
                    )
                return outgoing
            }
        button.configuration = configuration
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.adjustsFontSizeToFitWidth = false
        button.accessibilityTraits.remove(.keyboardKey)
        button.accessibilityTraits.insert(.button)
    }

    private func configureUtilityKey(
        _ button: UIButton,
        systemImage: String,
        accessibilityLabel: String
    ) {
        configureKey(
            button,
            systemImage: systemImage,
            accessibilityLabel: accessibilityLabel
        )
        var configuration = button.configuration
        configuration?.contentInsets = .zero
        configuration?.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        button.configuration = configuration
        button.accessibilityTraits.remove(.keyboardKey)
        button.accessibilityTraits.insert(.button)
    }

    private func applyAppearance() {
        backgroundColor = Self.keyboardBackground
        layer.borderColor = Self.keyboardBorder.resolvedColor(
            with: traitCollection
        ).cgColor
        layer.borderWidth = 1 / max(traitCollection.displayScale, 1)
        updateKeyAppearance(in: self)
        updateQuickInsertButtonPresentation()
        updateAutoButtonPresentation()
        setNeedsDisplay()
    }

    private func updateKeyAppearance(in root: UIView) {
        for subview in root.subviews {
            if let button = subview as? UIButton,
               var configuration = button.configuration {
                configuration.baseBackgroundColor = keyBackground(
                    for: button
                )
                configuration.baseForegroundColor = Self.keyForeground
                button.configuration = configuration
                button.layer.borderColor = Self.keyBorder.resolvedColor(
                    with: traitCollection
                ).cgColor
                button.layer.borderWidth = UIAccessibility
                    .isDarkerSystemColorsEnabled ? 1.5 : 0.5
                button.layer.shadowColor = Self.keyShadow.resolvedColor(
                    with: traitCollection
                ).cgColor
                button.layer.shadowOpacity = traitCollection.userInterfaceStyle
                    == .dark ? 0.30 : 0.18
                button.layer.shadowOffset = CGSize(width: 0, height: 1)
                button.layer.shadowRadius = 1.5
            }
            updateKeyAppearance(in: subview)
        }
    }

    private func keyBackground(for button: UIButton) -> UIColor {
        if button === latestButton
            || button === quickInsertButton
            || button === autoButton {
            return Self.topActionBackground
        }
        if quickInsertButtons.contains(where: { $0 === button }) {
            return Self.punctuationKeyBackground
        }
        return Self.editingKeyBackground
    }

    @objc private func latestTapped() {
        onLatestRequested?()
    }

    @objc private func quickInsertToggled() {
        guard quickInsertButton.isEnabled else { return }
        dismissAutomaticModesPanel(restoreAccessibilityFocus: false)
        quickInsertIsPresented.toggle()
        updateWorkspaceVisibility()
        updateQuickInsertButtonPresentation()
        UIAccessibility.post(
            notification: .layoutChanged,
            argument: quickInsertIsPresented
                ? quickInsertButtons.first
                : activeVoiceAccessibilityTarget
        )
    }

    func toggleAutomaticTranslation() {
        guard autoButton.isEnabled else { return }
        closeQuickInsert()
        onAutomaticVoiceActionChanged?(
            renderedAutomaticVoiceAction.togglingTranslation()
        )
        automaticModesPanel.render(renderedAutomaticVoiceAction)
    }

    func toggleAutomaticCorrection() {
        guard autoButton.isEnabled else { return }
        closeQuickInsert()
        onAutomaticVoiceActionChanged?(
            renderedAutomaticVoiceAction.togglingCorrection()
        )
        automaticModesPanel.render(renderedAutomaticVoiceAction)
    }

    @objc private func autoToggled() {
        guard autoButton.isEnabled else { return }
        if automaticModesArePresented {
            dismissAutomaticModesPanel()
        } else {
            closeQuickInsert()
            automaticModesArePresented = true
            updateAutomaticModesVisibility()
            UIAccessibility.post(
                notification: .screenChanged,
                argument: automaticModesPanel.firstAccessibilityTarget
            )
        }
    }

    @objc private func automaticModesDismissed() {
        dismissAutomaticModesPanel()
    }

    private func dismissAutomaticModesPanel(
        restoreAccessibilityFocus: Bool = true
    ) {
        guard automaticModesArePresented else { return }
        automaticModesArePresented = false
        updateAutomaticModesVisibility()
        if restoreAccessibilityFocus {
            UIAccessibility.post(
                notification: .layoutChanged,
                argument: autoButton
            )
        }
    }

    private func updateAutomaticModesVisibility() {
        automaticModesDismissControl.isHidden = !automaticModesArePresented
        automaticModesPanel.isHidden = !automaticModesArePresented
        automaticModesPanel.accessibilityElementsHidden =
            !automaticModesArePresented
    }

    private func handleQuickInsertSelection(_ text: String) {
        onQuickInsertRequested?(text)
        closeQuickInsert()
        UIAccessibility.post(
            notification: .layoutChanged,
            argument: activeVoiceAccessibilityTarget
        )
    }

    private func closeQuickInsert() {
        guard quickInsertIsPresented else { return }
        quickInsertIsPresented = false
        updateWorkspaceVisibility()
        updateQuickInsertButtonPresentation()
    }

    private func updateQuickInsertButtonPresentation() {
        var configuration = quickInsertButton.configuration
        configuration?.image = UIImage(
            systemName: quickInsertIsPresented ? "xmark" : "face.smiling"
        )
        quickInsertButton.configuration = configuration
        quickInsertButton.accessibilityLabel = quickInsertIsPresented
            ? "Close Quick Insert"
            : "Open Quick Insert"
        quickInsertButton.accessibilityValue = quickInsertIsPresented
            ? "Open"
            : "Closed"
        quickInsertButton.layer.borderColor = (
            quickInsertIsPresented
                ? Self.quickInsertActiveBorder
                : Self.keyBorder
        ).resolvedColor(with: traitCollection).cgColor
        quickInsertButton.layer.borderWidth = quickInsertIsPresented
            ? 2
            : (UIAccessibility.isDarkerSystemColorsEnabled ? 1.5 : 0.5)
    }

    private func updateAutoButtonPresentation() {
        let selectedCount = renderedAutomaticVoiceAction
            .selectedAutomaticModeCount
        var configuration = autoButton.configuration
        configuration?.title = selectedCount == 0
            ? "Auto"
            : "Auto \(selectedCount)"
        autoButton.configuration = configuration
        autoButton.accessibilityValue = automaticVoiceActionAccessibilityValue
        automaticModesPanel.render(renderedAutomaticVoiceAction)
    }

    private var automaticVoiceActionAccessibilityValue: String {
        let selectedModes = [
            renderedAutomaticVoiceAction.translates ? "Translate" : nil,
            renderedAutomaticVoiceAction.corrects ? "Correct" : nil,
        ].compactMap { $0 }
        return selectedModes.isEmpty
            ? "Off"
            : selectedModes.joined(separator: ", ")
    }

    private var activeVoiceAccessibilityTarget: UIView {
        microphoneView
    }

    @objc private func microphoneTapped() {
        onMicrophoneRequested?()
    }

    @objc private func cancelTapped() {
        onCancelRequested?()
    }

    @objc private func spaceTapped() {
        onSpaceRequested?()
    }

    @objc private func spaceCursorGestureChanged(
        _ gesture: UILongPressGestureRecognizer
    ) {
        onSpaceCursorGesture?(gesture.state, gesture.location(in: spaceButton).x)
    }

    @objc private func moveCursorLeft() -> Bool {
        onCursorStepRequested?(-1)
        return true
    }

    @objc private func moveCursorRight() -> Bool {
        onCursorStepRequested?(1)
        return true
    }

    @objc private func deleteStarted() {
        onDeleteStarted?()
    }

    @objc private func deleteStopped() {
        onDeleteStopped?()
    }

    @objc private func returnTapped() {
        onReturnRequested?()
    }

    private static let keyboardBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.035, green: 0.055, blue: 0.10, alpha: 1)
            : UIColor(red: 0.90, green: 0.915, blue: 0.95, alpha: 1)
    }

    private static let keyboardBorder = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.16)
            : UIColor(red: 0.69, green: 0.72, blue: 0.79, alpha: 1)
    }

    private static let topActionBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.105, green: 0.12, blue: 0.17, alpha: 1)
            : UIColor(red: 0.975, green: 0.98, blue: 0.995, alpha: 1)
    }

    private static let punctuationKeyBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.145, blue: 0.19, alpha: 1)
            : UIColor(red: 0.985, green: 0.99, blue: 1, alpha: 1)
    }

    private static let editingKeyBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.18, green: 0.195, blue: 0.24, alpha: 1)
            : .white
    }

    private static let keyForeground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .white
            : UIColor(red: 0.13, green: 0.15, blue: 0.20, alpha: 1)
    }

    private static let keyBorder = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.16)
            : UIColor(red: 0.73, green: 0.76, blue: 0.83, alpha: 1)
    }

    private static let quickInsertActiveBorder = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.42, blue: 1, alpha: 1)
            : UIColor(red: 0.42, green: 0.36, blue: 0.96, alpha: 1)
    }

    private static let keyShadow = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0, alpha: 0.8)
            : UIColor(red: 0.24, green: 0.28, blue: 0.38, alpha: 0.7)
    }

    private static let statusForeground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.84, green: 0.86, blue: 0.91, alpha: 1)
            : UIColor(red: 0.30, green: 0.33, blue: 0.42, alpha: 1)
    }

    private static let voiceForeground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.91, green: 0.92, blue: 0.98, alpha: 1)
            : UIColor(red: 0.30, green: 0.37, blue: 0.70, alpha: 1)
    }

}
