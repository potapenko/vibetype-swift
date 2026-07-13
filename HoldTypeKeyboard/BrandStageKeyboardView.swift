import UIKit

struct BrandStageKeyboardPresentation: Equatable {
    let status: KeyboardTopRailStatus
    let latestIsEnabled: Bool
    let returnKey: KeyboardReturnKeyPresentation
    let returnIsEnabled: Bool
    let showsInputModeSwitchKey: Bool
}

/// The selected Brand Stage Adaptive composition. The controller owns document
/// proxy behavior; this view owns only layout, appearance, and touch routing.
final class BrandStageKeyboardView: UIView {
    var onHistoryRequested: (() -> Void)?
    var onLatestRequested: (() -> Void)?
    var onPunctuationRequested: ((String) -> Void)?
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
    private let punctuationRow = UIStackView()
    private let historyButton = UIButton(type: .system)
    private let latestButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let logoImageView = UIImageView()
    private let stageContainer = UIView()
    private let voiceStage = UIStackView()
    private let editingRow = UIStackView()
    private let spaceButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let returnButton = UIButton(type: .system)
    private let microphoneView = UIView()
    private let microphoneImageView = UIImageView()
    private let waveformStack = UIStackView()
    private var preferredHeightConstraint: NSLayoutConstraint?
    private var topActionWidthConstraint: NSLayoutConstraint?
    private var logoWidthConstraint: NSLayoutConstraint?
    private var logoHeightConstraint: NSLayoutConstraint?
    private var rootTopConstraint: NSLayoutConstraint?
    private var rootBottomConstraint: NSLayoutConstraint?
    private var compactLayoutConstraints: [NSLayoutConstraint] = []
    private var usesCompactPhoneLayout: Bool?
    private var editingRowWithGlobeConstraints: [NSLayoutConstraint] = []
    private var editingRowWithoutGlobeConstraints: [NSLayoutConstraint] = []
    private var showsGlobeInEditingRow: Bool?
    private var punctuationButtons: [UIButton] = []
    private var reduceTransparencyObserver: NSObjectProtocol?
    private var renderedStatus: KeyboardTopRailStatus?

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
        statusLabel.text = presentation.status.rawValue
        statusLabel.accessibilityValue = presentation.status.rawValue
        latestButton.isEnabled = presentation.latestIsEnabled
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
    }

    func updatePreferredHeight(for traitCollection: UITraitCollection) {
        let isCompactPhone = traitCollection.userInterfaceIdiom == .phone
            && traitCollection.verticalSizeClass == .compact
        topActionWidthConstraint?.constant = traitCollection
            .preferredContentSizeCategory.isAccessibilityCategory ? 104 : 88
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
        logoWidthConstraint?.constant = isCompactPhone ? 28 : 34
        logoHeightConstraint?.constant = isCompactPhone ? 28 : 34
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
        stageContainer.translatesAutoresizingMaskIntoConstraints = false
        stageContainer.addSubview(voiceStage)
        let stageMinimumHeight = stageContainer.heightAnchor.constraint(
            greaterThanOrEqualToConstant: 96
        )
        let voiceFillsAvailableWidth = voiceStage.widthAnchor.constraint(
            equalTo: stageContainer.widthAnchor
        )
        voiceFillsAvailableWidth.priority = UILayoutPriority(999)
        let voicePrefersMaximumWidth = voiceStage.widthAnchor.constraint(
            equalToConstant: 520
        )
        voicePrefersMaximumWidth.priority = UILayoutPriority(998)
        let voiceStageConstraints = [
            voiceStage.leadingAnchor.constraint(
                greaterThanOrEqualTo: stageContainer.leadingAnchor
            ),
            voiceStage.trailingAnchor.constraint(
                lessThanOrEqualTo: stageContainer.trailingAnchor
            ),
            voiceStage.centerXAnchor.constraint(
                equalTo: stageContainer.centerXAnchor
            ),
            voiceStage.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            voiceFillsAvailableWidth,
            voicePrefersMaximumWidth,
            voiceStage.topAnchor.constraint(equalTo: stageContainer.topAnchor),
            voiceStage.bottomAnchor.constraint(equalTo: stageContainer.bottomAnchor),
        ]
        NSLayoutConstraint.activate(voiceStageConstraints + [stageMinimumHeight])

        let punctuationRow = makePunctuationRow()
        let editingRow = makeEditingRow()
        commandStack.axis = .vertical
        commandStack.alignment = .fill
        commandStack.distribution = .fill
        commandStack.spacing = 10
        commandStack.addArrangedSubview(punctuationRow)
        commandStack.addArrangedSubview(editingRow)

        bodyStack.axis = .vertical
        bodyStack.alignment = .fill
        bodyStack.distribution = .fill
        bodyStack.spacing = 10
        bodyStack.addArrangedSubview(stageContainer)
        bodyStack.addArrangedSubview(commandStack)

        rootStack.addArrangedSubview(topRail)
        rootStack.addArrangedSubview(bodyStack)

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
            punctuationRow.heightAnchor.constraint(equalToConstant: 44),
            editingRow.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    private func makeTopRail() -> UIStackView {
        configureTopAction(
            historyButton,
            title: "History",
            systemImage: "clock",
            accessibilityLabel: "Open History in HoldType"
        )
        historyButton.accessibilityIdentifier = "keyboard.brand-stage.history"
        historyButton.accessibilityHint =
            "Opens HoldType and shows your transcription history."
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
        statusLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: UIFont.systemFont(ofSize: 12, weight: .semibold),
            maximumPointSize: 15
        )
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.8
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 1
        statusLabel.isAccessibilityElement = true
        statusLabel.accessibilityLabel = "Keyboard status"
        statusLabel.accessibilityTraits.insert(.updatesFrequently)
        statusLabel.accessibilityIdentifier = "keyboard.brand-stage.status"

        let identity = UIStackView(
            arrangedSubviews: [logoImageView, statusLabel]
        )
        identity.axis = .vertical
        identity.alignment = .center
        identity.spacing = 2
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

        let rail = UIStackView(
            arrangedSubviews: [historyButton, identity, latestButton]
        )
        rail.axis = .horizontal
        rail.alignment = .center
        rail.distribution = .equalCentering
        rail.spacing = 8
        let topActionWidth = historyButton.widthAnchor.constraint(
            equalToConstant: 88
        )
        topActionWidthConstraint = topActionWidth
        NSLayoutConstraint.activate([
            topActionWidth,
            latestButton.widthAnchor.constraint(equalTo: historyButton.widthAnchor),
            historyButton.heightAnchor.constraint(equalToConstant: 44),
            latestButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        return rail
    }

    private func configureVoiceStage() {
        voiceStage.translatesAutoresizingMaskIntoConstraints = false
        voiceStage.axis = .horizontal
        voiceStage.alignment = .center
        voiceStage.distribution = .fill
        voiceStage.spacing = 12

        configureWaveform()
        let leftWaveform = waveformStack
        let rightWaveform = mirroredWaveform()
        voiceStage.addArrangedSubview(leftWaveform)
        voiceStage.addArrangedSubview(microphoneView)
        voiceStage.addArrangedSubview(rightWaveform)
        leftWaveform.widthAnchor.constraint(greaterThanOrEqualToConstant: 96)
            .isActive = true
        rightWaveform.widthAnchor.constraint(equalTo: leftWaveform.widthAnchor)
            .isActive = true
        microphoneView.widthAnchor.constraint(equalToConstant: 80).isActive = true
        microphoneView.heightAnchor.constraint(equalToConstant: 80).isActive = true

        microphoneView.layer.cornerRadius = 40
        microphoneView.layer.cornerCurve = .continuous
        microphoneView.layer.borderWidth = 2
        microphoneView.layer.masksToBounds = false
        microphoneView.isUserInteractionEnabled = false
        microphoneView.isAccessibilityElement = false
        microphoneView.accessibilityIdentifier = "keyboard.brand-stage.voice"
        microphoneImageView.translatesAutoresizingMaskIntoConstraints = false
        microphoneImageView.image = UIImage(systemName: "mic.fill")
        microphoneImageView.contentMode = .scaleAspectFit
        microphoneView.addSubview(microphoneImageView)
        NSLayoutConstraint.activate([
            microphoneImageView.centerXAnchor.constraint(equalTo: microphoneView.centerXAnchor),
            microphoneImageView.centerYAnchor.constraint(equalTo: microphoneView.centerYAnchor),
            microphoneImageView.widthAnchor.constraint(equalToConstant: 34),
            microphoneImageView.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    private func makePunctuationRow() -> UIStackView {
        punctuationRow.axis = .horizontal
        punctuationRow.distribution = .fillEqually
        punctuationRow.spacing = 8
        for (character, name) in [
            (".", "Period"),
            (",", "Comma"),
            ("?", "Question mark"),
            ("!", "Exclamation mark"),
        ] {
            let button = UIButton(type: .system)
            configureKey(button, title: character, accessibilityLabel: name)
            button.accessibilityIdentifier =
                "keyboard.brand-stage.punctuation.\(name.lowercased())"
            button.addAction(UIAction { [weak self] _ in
                self?.onPunctuationRequested?(character)
            }, for: .touchUpInside)
            punctuationButtons.append(button)
            punctuationRow.addArrangedSubview(button)
        }
        return punctuationRow
    }

    private func makeEditingRow() -> UIStackView {
        configureKey(
            nextKeyboardButton,
            systemImage: "globe",
            accessibilityLabel: "Next keyboard"
        )
        configureKey(
            spaceButton,
            systemImage: "circle.grid.3x3.fill",
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

    private func configureWaveform() {
        waveformStack.axis = .horizontal
        waveformStack.alignment = .center
        waveformStack.distribution = .equalCentering
        waveformStack.spacing = 3
        for height in Self.waveformHeights {
            waveformStack.addArrangedSubview(makeWaveformBar(height: height))
        }
    }

    private func mirroredWaveform() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalCentering
        stack.spacing = 3
        for height in Self.waveformHeights.reversed() {
            stack.addArrangedSubview(makeWaveformBar(height: height))
        }
        return stack
    }

    private func makeWaveformBar(height: CGFloat) -> UIView {
        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.backgroundColor = Self.waveformColor
        bar.layer.cornerRadius = 1
        NSLayoutConstraint.activate([
            bar.widthAnchor.constraint(equalToConstant: 2),
            bar.heightAnchor.constraint(equalToConstant: height),
        ])
        return bar
    }

    private func configureInteractions() {
        historyButton.addTarget(
            self,
            action: #selector(historyTapped),
            for: .touchUpInside
        )
        latestButton.addTarget(
            self,
            action: #selector(latestTapped),
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
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.82
        button.accessibilityTraits.remove(.keyboardKey)
        button.accessibilityTraits.insert(.button)
    }

    private func applyAppearance() {
        backgroundColor = Self.keyboardBackground
        layer.borderColor = Self.keyboardBorder.resolvedColor(
            with: traitCollection
        ).cgColor
        layer.borderWidth = 1 / max(traitCollection.displayScale, 1)
        statusLabel.textColor = Self.statusForeground
        microphoneView.backgroundColor = Self.microphoneBackground
        microphoneImageView.tintColor = Self.voiceForeground
        microphoneView.layer.borderColor = Self.microphoneBorder.resolvedColor(
            with: traitCollection
        ).cgColor
        microphoneView.layer.shadowColor = Self.microphoneGlow.resolvedColor(
            with: traitCollection
        ).cgColor
        microphoneView.layer.shadowOpacity = traitCollection.userInterfaceStyle
            == .dark ? 0.34 : 0.24
        microphoneView.layer.shadowOffset = .zero
        microphoneView.layer.shadowRadius = 8
        let contrast = UIAccessibility.isDarkerSystemColorsEnabled
        microphoneView.layer.borderWidth = contrast ? 3 : 2
        updateKeyAppearance(in: self)
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
        if button === historyButton || button === latestButton {
            return Self.topActionBackground
        }
        if punctuationButtons.contains(where: { $0 === button }) {
            return Self.punctuationKeyBackground
        }
        return Self.editingKeyBackground
    }

    @objc private func historyTapped() {
        onHistoryRequested?()
    }

    @objc private func latestTapped() {
        onLatestRequested?()
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

    private static let waveformColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.63, blue: 0.88, alpha: 0.72)
            : UIColor(red: 0.37, green: 0.45, blue: 0.78, alpha: 0.58)
    }

    private static let microphoneBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.15, blue: 0.29, alpha: 1)
            : UIColor(red: 0.955, green: 0.965, blue: 1, alpha: 1)
    }

    private static let microphoneBorder = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.52, green: 0.30, blue: 0.95, alpha: 0.48)
            : UIColor(red: 0.32, green: 0.40, blue: 0.91, alpha: 0.62)
    }

    private static let voiceForeground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.91, green: 0.92, blue: 0.98, alpha: 1)
            : UIColor(red: 0.30, green: 0.37, blue: 0.70, alpha: 1)
    }

    private static let microphoneGlow = UIColor { _ in
        UIColor(red: 0.38, green: 0.34, blue: 0.95, alpha: 1)
    }

    private static let waveformHeights: [CGFloat] = [
        3, 4, 5, 6, 8, 10, 14, 20, 28, 36, 24,
        30, 22, 18, 16, 12, 9, 7, 5, 4, 3,
    ]
}
