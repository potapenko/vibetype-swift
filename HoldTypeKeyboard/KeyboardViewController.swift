//
//  KeyboardViewController.swift
//  HoldTypeKeyboard
//
//  Created by Codex on 7/9/26.
//

import UIKit

final class KeyboardViewController: UIInputViewController {
    private let statusLabel = UILabel()
    private let insertTranscriptButton = UIButton(type: .system)
    private let nextKeyboardButton = UIButton(type: .system)
    private var acceptedTranscript: KeyboardBridgeTranscript?

    override func viewDidLoad() {
        super.viewDidLoad()

        hasDictationKey = false
        configureInterface()
        reloadSharedSnapshot()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSharedSnapshot()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        nextKeyboardButton.isHidden = !needsInputModeSwitchKey
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        reloadSharedSnapshot()
    }

    private func configureInterface() {
        view.backgroundColor = .secondarySystemBackground

        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 2
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let refreshButton = makeButton(
            title: "Refresh",
            systemImage: "arrow.clockwise",
            action: #selector(refreshTapped)
        )

        let statusRow = UIStackView(arrangedSubviews: [statusLabel, refreshButton])
        statusRow.axis = .horizontal
        statusRow.alignment = .center
        statusRow.spacing = 8

        configureButton(
            insertTranscriptButton,
            title: "Insert latest",
            systemImage: "text.badge.checkmark",
            action: #selector(insertTranscriptTapped),
            prominent: true
        )

        let characterButton = makeButton(
            title: "a",
            action: #selector(characterTapped)
        )
        characterButton.accessibilityLabel = "Letter a"

        let spaceButton = makeButton(
            title: "space",
            action: #selector(spaceTapped)
        )

        let deleteButton = makeButton(
            title: "Delete",
            systemImage: "delete.left",
            action: #selector(deleteTapped)
        )

        configureButton(
            nextKeyboardButton,
            title: "Next keyboard",
            systemImage: "globe",
            action: nil
        )
        nextKeyboardButton.addTarget(
            self,
            action: #selector(handleInputModeList(from:with:)),
            for: .allTouchEvents
        )
        nextKeyboardButton.accessibilityLabel = "Next keyboard"

        let inputRow = UIStackView(
            arrangedSubviews: [nextKeyboardButton, characterButton, spaceButton, deleteButton]
        )
        inputRow.axis = .horizontal
        inputRow.distribution = .fillEqually
        inputRow.spacing = 6

        let rootStack = UIStackView(
            arrangedSubviews: [statusRow, insertTranscriptButton, inputRow]
        )
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.axis = .vertical
        rootStack.spacing = 8

        view.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8),
            insertTranscriptButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            inputRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    private func makeButton(
        title: String,
        systemImage: String? = nil,
        action: Selector
    ) -> UIButton {
        let button = UIButton(type: .system)
        configureButton(
            button,
            title: title,
            systemImage: systemImage,
            action: action
        )
        return button
    }

    private func configureButton(
        _ button: UIButton,
        title: String,
        systemImage: String? = nil,
        action: Selector?,
        prominent: Bool = false
    ) {
        var configuration = prominent
            ? UIButton.Configuration.filled()
            : UIButton.Configuration.gray()
        configuration.title = title
        configuration.image = systemImage.flatMap { UIImage(systemName: $0) }
        configuration.imagePadding = 6
        configuration.cornerStyle = .medium
        button.configuration = configuration

        if let action {
            button.addTarget(self, action: action, for: .touchUpInside)
        }
    }

    private func reloadSharedSnapshot() {
        do {
            let store = try KeyboardBridgeStore.appGroup()
            acceptedTranscript = try store.load()?.transcriptForInsertion()

            if acceptedTranscript == nil {
                statusLabel.text = "Publish a sample from the HoldType app."
            } else {
                statusLabel.text = "Accepted transcript is ready."
            }
        } catch {
            acceptedTranscript = nil
            statusLabel.text = "Shared state is unavailable."
        }

        insertTranscriptButton.isEnabled = acceptedTranscript != nil
    }

    @objc private func refreshTapped() {
        reloadSharedSnapshot()
    }

    @objc private func insertTranscriptTapped() {
        guard let acceptedTranscript else {
            return
        }

        textDocumentProxy.insertText(acceptedTranscript.text)
        statusLabel.text = "Transcript inserted."
    }

    @objc private func characterTapped() {
        textDocumentProxy.insertText("a")
    }

    @objc private func spaceTapped() {
        textDocumentProxy.insertText(" ")
    }

    @objc private func deleteTapped() {
        textDocumentProxy.deleteBackward()
    }
}
