//
//  FakeGlobalHotkeyService.swift
//  vibetypeTests
//
//  Created by Codex on 6/20/26.
//

@testable import vibetype

final class FakeGlobalHotkeyService: GlobalHotkeyService {
    private var actionHandler: GlobalHotkeyActionHandler?

    private(set) var startListeningCount = 0
    private(set) var stopListeningCount = 0
    private(set) var triggeredActions: [GlobalHotkeyAction] = []
    private(set) var currentRegistrationStatus: GlobalHotkeyRegistrationStatus

    var preferredConfiguration: GlobalHotkeyConfiguration
    var startListeningResult: Result<GlobalHotkeyRegistrationStatus, GlobalHotkeyServiceError>

    init(
        preferredConfiguration: GlobalHotkeyConfiguration = .defaultDictation,
        currentRegistrationStatus: GlobalHotkeyRegistrationStatus = .notRegistered,
        startListeningResult: Result<GlobalHotkeyRegistrationStatus, GlobalHotkeyServiceError> = .success(
            .registered(.defaultDictation)
        )
    ) {
        self.preferredConfiguration = preferredConfiguration
        self.currentRegistrationStatus = currentRegistrationStatus
        self.startListeningResult = startListeningResult
    }

    func startListening(actionHandler: @escaping GlobalHotkeyActionHandler) throws {
        startListeningCount += 1

        do {
            currentRegistrationStatus = try startListeningResult.get()
            self.actionHandler = actionHandler
        } catch let error as GlobalHotkeyServiceError {
            currentRegistrationStatus = .unavailable(
                message: error.errorDescription ?? error.localizedDescription
            )
            self.actionHandler = nil
            throw error
        }
    }

    func stopListening() {
        stopListeningCount += 1
        currentRegistrationStatus = .notRegistered
        actionHandler = nil
    }

    func trigger(_ action: GlobalHotkeyAction) {
        triggeredActions.append(action)
        actionHandler?(action)
    }
}
