//
//  FloatingIndicatorCoordinator.swift
//  HoldType
//
//  Created by Codex on 7/7/26.
//

import Combine
import Foundation

@MainActor
final class FloatingIndicatorCoordinator {
    static let shared = FloatingIndicatorCoordinator()

    private let dictationRuntime: DictationRuntime
    private let appSettingsStore: AppSettingsStore
    private let presenter: any FloatingIndicatorPresenting

    private var appSettings: AppSettings
    private var cancellables: Set<AnyCancellable> = []
    private var isStarted = false
    private var hasDeliveredPresentation = false
    private var lastDeliveredPresentation: FloatingIndicatorPresentation?

    convenience init() {
        self.init(
            dictationRuntime: .shared,
            appSettingsStore: AppSettingsStore(),
            presenter: FloatingIndicatorPanelController()
        )
    }

    init(
        dictationRuntime: DictationRuntime,
        appSettingsStore: AppSettingsStore,
        presenter: any FloatingIndicatorPresenting
    ) {
        self.dictationRuntime = dictationRuntime
        self.appSettingsStore = appSettingsStore
        self.presenter = presenter
        self.appSettings = appSettingsStore.load()
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        appSettings = appSettingsStore.load()

        dictationRuntime.$status
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.update()
                }
            }
            .store(in: &cancellables)

        dictationRuntime.$recordingCountdown
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.update()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .appSettingsDidChange)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else {
                        return
                    }

                    self.appSettings = self.appSettingsStore.load()
                    self.update()
                }
            }
            .store(in: &cancellables)

        update()
    }

    func stop() {
        guard isStarted else {
            return
        }

        isStarted = false
        cancellables.removeAll()
        hasDeliveredPresentation = false
        lastDeliveredPresentation = nil
        presenter.hide()
    }

    private func update() {
        let presentation = FloatingIndicatorPresentation.presentation(
            for: dictationRuntime.status,
            settings: appSettings,
            recordingCountdown: dictationRuntime.recordingCountdown
        )
        guard !hasDeliveredPresentation || presentation != lastDeliveredPresentation else {
            return
        }

        hasDeliveredPresentation = true
        lastDeliveredPresentation = presentation
        presenter.update(with: presentation)
    }
}
