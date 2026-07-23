import Foundation
import Observation
import UIKit

/// Process-owned lifecycle shell for keyboard Fix metadata and one current
/// app-mediated request. It does not own or mutate Voice presentation state.
@MainActor
@Observable
final class IOSKeyboardFixRuntimeOwner {
    @ObservationIgnored
    private let processor: IOSKeyboardFixProcessor
    @ObservationIgnored
    private let metadataPublisher: IOSKeyboardFixMetadataPublisher
    @ObservationIgnored
    private let requestObservation: IOSKeyboardFixRequestObservationClient
    @ObservationIgnored
    private let backgroundTaskRegistry:
        IOSKeyboardFixBackgroundTaskRegistry?

    @ObservationIgnored
    private var processingTask: Task<Void, Never>?
    @ObservationIgnored
    private var metadataTask: Task<Void, Never>?
    @ObservationIgnored
    private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored
    private var hasPendingProcessSignal = false
    @ObservationIgnored
    private var hasPendingCancellationSignal = false
    @ObservationIgnored
    private var hasPendingMetadataRefresh = false
    @ObservationIgnored
    private var isStarted = false

    init(
        processor: IOSKeyboardFixProcessor,
        metadataPublisher: IOSKeyboardFixMetadataPublisher,
        requestObservation: IOSKeyboardFixRequestObservationClient,
        backgroundTaskRegistry:
            IOSKeyboardFixBackgroundTaskRegistry? = nil
    ) {
        self.processor = processor
        self.metadataPublisher = metadataPublisher
        self.requestObservation = requestObservation
        self.backgroundTaskRegistry = backgroundTaskRegistry
    }

    func handleSceneActivity(_ activity: IOSVoiceSceneActivity) {
        startIfNeeded()
        scheduleMetadataRefresh()
        if activity == .active {
            schedulePendingCancellationProcessing()
            schedulePendingRequestProcessing()
        }
    }

    @discardableResult
    func handleLaunchURL(_ url: URL) -> Bool {
        guard KeyboardFixLaunchRoute(url: url) != nil else {
            return false
        }
        startIfNeeded()
        scheduleMetadataRefresh()
        schedulePendingCancellationProcessing()
        schedulePendingRequestProcessing()
        return true
    }

    /// Editor integration seam. Call after the canonical repository save and
    /// Voice catalog refresh have both completed.
    @discardableResult
    func refreshCatalogMetadata() async -> Bool {
        await metadataPublisher.publishCurrent()
    }

    func waitUntilIdle() async {
        while processingTask != nil || metadataTask != nil {
            await Task.yield()
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        requestObservation.stop()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        processingTask?.cancel()
        metadataTask?.cancel()
        processingTask = nil
        metadataTask = nil
        hasPendingProcessSignal = false
        hasPendingCancellationSignal = false
        hasPendingMetadataRefresh = false
        backgroundTaskRegistry?.endAll()
        Task { [processor] in
            await processor.cancelActiveRequest()
        }
    }

    private func startIfNeeded() {
        guard !isStarted else { return }
        isStarted = true
        requestObservation.start { [weak self] signal in
            Task { @MainActor [weak self] in
                switch signal {
                case .requestChanged:
                    self?.schedulePendingRequestProcessing()
                case .cancellationChanged:
                    self?.schedulePendingCancellationProcessing()
                }
            }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
        scheduleMetadataRefresh()
        schedulePendingCancellationProcessing()
        schedulePendingRequestProcessing()
    }

    private func schedulePendingCancellationProcessing() {
        hasPendingCancellationSignal = true
        startCoordinationTaskIfNeeded()
    }

    private func schedulePendingRequestProcessing() {
        hasPendingProcessSignal = true
        startCoordinationTaskIfNeeded()
    }

    private func startCoordinationTaskIfNeeded() {
        guard processingTask == nil else { return }
        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while (
                hasPendingCancellationSignal || hasPendingProcessSignal
            ), !Task.isCancelled {
                if hasPendingCancellationSignal {
                    hasPendingCancellationSignal = false
                    _ = await processor.processPendingCancellation()
                }
                if hasPendingProcessSignal {
                    hasPendingProcessSignal = false
                    _ = await processor.processPendingRequest()
                }
            }
            processingTask = nil
        }
    }

    private func scheduleMetadataRefresh() {
        hasPendingMetadataRefresh = true
        guard metadataTask == nil else { return }
        metadataTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while hasPendingMetadataRefresh, !Task.isCancelled {
                hasPendingMetadataRefresh = false
                _ = await metadataPublisher.publishCurrent()
            }
            metadataTask = nil
        }
    }

    deinit {
        requestObservation.stop()
        processingTask?.cancel()
        metadataTask?.cancel()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }
}

nonisolated extension IOSKeyboardFixRuntimeOwner:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSKeyboardFixRuntimeOwner(redacted)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}
