//
//  KeyboardSessionState.swift
//  vibetype
//
//  Created by Codex on 6/21/26.
//

import Foundation

enum KeyboardSetupRequirement: Equatable {
    case containingAppSetupRequired
    case openAccessRequired
    case acceptedTranscriptUnavailable
    case hostInputUnavailable
}

enum KeyboardSessionError: Equatable {
    case setupRequired(KeyboardSetupRequirement)
    case emptyTranscript
    case containingAppSessionFailed
    case transcriptionFailed
}

struct KeyboardSessionAvailability: Equatable {
    let setupRequirement: KeyboardSetupRequirement?

    static let ready = KeyboardSessionAvailability(setupRequirement: nil)

    static func setupNeeded(_ requirement: KeyboardSetupRequirement) -> KeyboardSessionAvailability {
        KeyboardSessionAvailability(setupRequirement: requirement)
    }

    var canStartVoiceSession: Bool {
        setupRequirement == nil
    }
}

struct KeyboardAcceptedTranscript: Equatable, Identifiable {
    enum ValidationError: Error, Equatable {
        case emptyTranscriptText
    }

    let id: UUID
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) throws {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw ValidationError.emptyTranscriptText
        }

        self.id = id
        self.text = normalizedText
        self.createdAt = createdAt
    }
}

struct KeyboardTranscriptDraft: Equatable {
    let text: String

    init?(_ text: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return nil
        }

        self.text = normalizedText
    }
}

struct KeyboardInlineSettingsState: Equatable {
    let canOpenContainingApp: Bool
}

enum KeyboardSessionState: Equatable {
    case setupNeeded(KeyboardSetupRequirement)
    case idle(acceptedTranscript: KeyboardAcceptedTranscript?)
    case launchingSession
    case listening
    case transcribing
    case confirming(KeyboardTranscriptDraft)
    case acceptedTranscript(KeyboardAcceptedTranscript)
    case error(KeyboardSessionError, acceptedTranscript: KeyboardAcceptedTranscript?)
    case compactSettings(KeyboardInlineSettingsState)
}

enum KeyboardSessionDecision: Equatable {
    case none
    case requestContainingAppVoiceSession
    case openContainingApp
    case insertAcceptedTranscript(String)
    case unavailable(KeyboardSetupRequirement)
}

struct KeyboardSessionModel: Equatable {
    private let availability: KeyboardSessionAvailability
    private(set) var acceptedTranscript: KeyboardAcceptedTranscript?
    private(set) var state: KeyboardSessionState

    init(
        availability: KeyboardSessionAvailability = .ready,
        acceptedTranscript: KeyboardAcceptedTranscript? = nil
    ) {
        self.availability = availability
        self.acceptedTranscript = acceptedTranscript

        if let setupRequirement = availability.setupRequirement {
            self.state = .setupNeeded(setupRequirement)
        } else {
            self.state = .idle(acceptedTranscript: acceptedTranscript)
        }
    }

    mutating func start() -> KeyboardSessionDecision {
        if let setupRequirement = availability.setupRequirement {
            state = .setupNeeded(setupRequirement)
            return .unavailable(setupRequirement)
        }

        switch state {
        case .launchingSession, .listening, .transcribing, .confirming:
            return .none
        default:
            state = .launchingSession
            return .requestContainingAppVoiceSession
        }
    }

    mutating func sessionDidBeginListening() {
        guard state == .launchingSession else {
            return
        }

        state = .listening
    }

    mutating func beginTranscribing() {
        guard state == .listening else {
            return
        }

        state = .transcribing
    }

    mutating func finishTranscription(text: String) {
        guard state == .transcribing else {
            return
        }

        guard let draft = KeyboardTranscriptDraft(text) else {
            state = .error(.emptyTranscript, acceptedTranscript: acceptedTranscript)
            return
        }

        state = .confirming(draft)
    }

    mutating func accept() throws -> KeyboardSessionDecision {
        switch state {
        case .confirming(let draft):
            let accepted = try KeyboardAcceptedTranscript(text: draft.text)
            acceptedTranscript = accepted
            state = .acceptedTranscript(accepted)
            return .insertAcceptedTranscript(accepted.text)

        case .acceptedTranscript(let accepted):
            return .insertAcceptedTranscript(accepted.text)

        default:
            return .none
        }
    }

    mutating func cancel() {
        if let setupRequirement = availability.setupRequirement {
            state = .setupNeeded(setupRequirement)
            return
        }

        state = .idle(acceptedTranscript: acceptedTranscript)
    }

    mutating func fail(_ error: KeyboardSessionError) {
        state = .error(error, acceptedTranscript: acceptedTranscript)
    }

    mutating func openInlineSettings() {
        state = .compactSettings(
            KeyboardInlineSettingsState(canOpenContainingApp: true)
        )
    }

    mutating func closeInlineSettings() {
        cancel()
    }

    func openContainingApp() -> KeyboardSessionDecision {
        .openContainingApp
    }
}
