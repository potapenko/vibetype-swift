//
//  FakeGlobalHotkeyService.swift
//  HoldTypeTests
//
//  Created by Codex on 6/20/26.
//

import Foundation
import HoldTypeDomain
@testable import HoldType

final class FakeGlobalHotkeyService: GlobalHotkeyService {
    private var actionHandler: GlobalHotkeyActionHandler?

    private(set) var startListeningCount = 0
    private(set) var stopListeningCount = 0
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

        switch startListeningResult {
        case .success(let registrationStatus):
            currentRegistrationStatus = registrationStatus
            self.actionHandler = actionHandler
        case .failure(let error):
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
        actionHandler?(GlobalHotkeyEvent(action: action, outputIntent: .standard))
    }

    func trigger(_ event: GlobalHotkeyEvent) {
        actionHandler?(event)
    }
}
