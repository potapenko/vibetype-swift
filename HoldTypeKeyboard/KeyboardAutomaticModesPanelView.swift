import UIKit

/// Keyboard counterpart of the containing app's persistent Voice Auto popover.
final class KeyboardAutomaticModesPanelView: UIView {
    var onTranslationToggleRequested: (() -> Void)?
    var onCorrectionToggleRequested: (() -> Void)?
    var onDismissRequested: (() -> Void)?

    private let translationRow = KeyboardAutomaticModeRowView(
        title: "Translate Result",
        accessibilityLabel: "Auto Translate",
        systemImage: "character.bubble",
        identifier: "translate"
    )
    private let correctionRow = KeyboardAutomaticModeRowView(
        title: "Correct Result",
        accessibilityLabel: "Auto Correct",
        systemImage: "wand.and.stars",
        identifier: "correct"
    )
    private let divider = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
        configureInteractions()
        applyAppearance()
        registerForTraitChanges([
            UITraitUserInterfaceStyle.self,
            UITraitAccessibilityContrast.self,
        ]) { (view: KeyboardAutomaticModesPanelView, _) in
            view.applyAppearance()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func render(_ action: KeyboardVoiceAction) {
        translationRow.setOn(action.translates)
        correctionRow.setOn(action.corrects)
    }

    var firstAccessibilityTarget: UIView {
        translationRow.modeSwitch
    }

    override func accessibilityPerformEscape() -> Bool {
        onDismissRequested?()
        return true
    }

    private func configureHierarchy() {
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityIdentifier = "keyboard.brand-stage.auto-modes"
        accessibilityViewIsModal = true
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.masksToBounds = false

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.isAccessibilityElement = false

        let stack = UIStackView(arrangedSubviews: [
            translationRow,
            divider,
            correctionRow,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.distribution = .fill
        stack.spacing = 0
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            divider.heightAnchor.constraint(
                equalToConstant: 1 / max(traitCollection.displayScale, 1)
            ),
        ])
    }

    private func configureInteractions() {
        translationRow.onToggleRequested = { [weak self] in
            self?.onTranslationToggleRequested?()
        }
        correctionRow.onToggleRequested = { [weak self] in
            self?.onCorrectionToggleRequested?()
        }
    }

    private func applyAppearance() {
        backgroundColor = .secondarySystemBackground
        divider.backgroundColor = .separator
        layer.borderColor = UIColor.separator.resolvedColor(
            with: traitCollection
        ).cgColor
        layer.borderWidth = 1 / max(traitCollection.displayScale, 1)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark
            ? 0.34
            : 0.18
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 12
    }
}

private final class KeyboardAutomaticModeRowView: UIControl {
    let modeSwitch = UISwitch()

    var onToggleRequested: (() -> Void)?

    init(
        title: String,
        accessibilityLabel: String,
        systemImage: String,
        identifier: String
    ) {
        super.init(frame: .zero)
        configureHierarchy(
            title: title,
            accessibilityLabel: accessibilityLabel,
            systemImage: systemImage,
            identifier: identifier
        )
        configureInteractions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func setOn(_ isOn: Bool) {
        modeSwitch.setOn(isOn, animated: false)
    }

    private func configureHierarchy(
        title: String,
        accessibilityLabel: String,
        systemImage: String,
        identifier: String
    ) {
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityIdentifier =
            "keyboard.brand-stage.auto-mode-row.\(identifier)"
        isAccessibilityElement = false

        let imageView = UIImageView(
            image: UIImage(systemName: systemImage)
        )
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .label
        imageView.accessibilityIdentifier =
            "keyboard.brand-stage.auto-mode-icon.\(identifier)"
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            textStyle: .body,
            scale: .medium
        )
        imageView.isAccessibilityElement = false

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.accessibilityIdentifier =
            "keyboard.brand-stage.auto-mode-title.\(identifier)"
        titleLabel.textColor = .label
        titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.systemFont(ofSize: 17),
            maximumPointSize: 23
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        titleLabel.isAccessibilityElement = false

        modeSwitch.translatesAutoresizingMaskIntoConstraints = false
        modeSwitch.accessibilityLabel = accessibilityLabel
        modeSwitch.accessibilityIdentifier =
            "keyboard.brand-stage.auto-mode.\(identifier)"
        modeSwitch.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )

        addSubview(imageView)
        addSubview(titleLabel)
        addSubview(modeSwitch)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            imageView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 16
            ),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20),
            titleLabel.leadingAnchor.constraint(
                equalTo: imageView.trailingAnchor,
                constant: 12
            ),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: modeSwitch.leadingAnchor,
                constant: -12
            ),
            modeSwitch.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -16
            ),
            modeSwitch.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func configureInteractions() {
        addTarget(
            self,
            action: #selector(rowTapped),
            for: .touchUpInside
        )
        modeSwitch.addTarget(
            self,
            action: #selector(switchChanged),
            for: .valueChanged
        )
    }

    @objc private func rowTapped() {
        modeSwitch.setOn(!modeSwitch.isOn, animated: true)
        onToggleRequested?()
    }

    @objc private func switchChanged() {
        onToggleRequested?()
    }
}
