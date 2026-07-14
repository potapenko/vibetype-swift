import AVFAudio
import Combine
import Foundation
import UIKit

/// DEBUG feasibility owner for KBD-MVP-2. The containing app alone owns the
/// microphone, temporary audio file, bounded background assertion, and state.
@MainActor
final class IOSKeyboardDictationSessionCoordinator: ObservableObject {
    enum Presentation: Equatable {
        case stopped
        case preparing
        case ready(Date)
        case listening(Date)
        case processing
        case failed(String)

        var title: String {
            switch self {
            case .stopped:
                return "Stopped"
            case .preparing:
                return "Preparing…"
            case .ready:
                return "Ready for HoldType Keyboard"
            case .listening:
                return "Listening…"
            case .processing:
                return "Finishing…"
            case let .failed(message):
                return message
            }
        }
    }

    @Published private(set) var presentation: Presentation = .stopped

    private let store: KeyboardDictationBridgeStore?
    private var commandObserver: KeyboardDictationBridgeObserver?
    private var interruptionObserver: NSObjectProtocol?
    private var requestID: UUID?
    private var deadline: Date?
    private var expiryTimer: Timer?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var lastHandledCommand: KeyboardDictationCommandRecord?

    init(store: KeyboardDictationBridgeStore? = try? .appGroup()) {
        self.store = store
        commandObserver = KeyboardDictationBridgeObserver(
            name: KeyboardDictationBridgeConfiguration.commandNotification
        ) { [weak self] in
            self?.receiveCurrentCommand()
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let raw = notification.userInfo?[
                    AVAudioSessionInterruptionTypeKey
                ] as? UInt,
                AVAudioSession.InterruptionType(rawValue: raw) == .began else {
                    return
                }
                self?.failAndStop("Audio interrupted")
            }
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    func startSession() async {
        guard UIApplication.shared.applicationState == .active else {
            presentation = .failed("Open HoldType")
            return
        }
        stopSession(publishUnavailable: false)
        presentation = .preparing

        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { _ in
                    continuation.resume()
                }
            }
        case .denied, .granted:
            break
        @unknown default:
            presentation = .failed("Microphone unavailable")
            return
        }

        guard AVAudioApplication.shared.recordPermission == .granted else {
            presentation = .failed("Allow Microphone")
            return
        }
        guard store != nil else {
            presentation = .failed("App Group unavailable")
            return
        }

        let now = Date()
        let requestID = UUID()
        let deadline = now.addingTimeInterval(
            KeyboardDictationBridgeConfiguration.sessionLifetime
        )
        self.requestID = requestID
        self.deadline = deadline
        lastHandledCommand = nil
        beginBackgroundTask()
        scheduleExpiry(at: deadline)
        guard publish(
            phase: .ready,
            requestID: requestID,
            publishedAt: now,
            expiresAt: deadline
        ) else {
            failAndStop("Session unavailable")
            return
        }
        presentation = .ready(deadline)
    }

    func stopSession() {
        stopSession(publishUnavailable: true)
    }

    private func receiveCurrentCommand() {
        guard let store,
              let requestID,
              let deadline,
              deadline > Date(),
              let command = try? store.loadCommand(),
              command.requestID == requestID,
              command != lastHandledCommand else {
            return
        }
        lastHandledCommand = command
        switch command.kind {
        case .start:
            startRecording(requestID: requestID, deadline: deadline)
        case .finish:
            finishRecording(requestID: requestID, deadline: deadline)
        case .cancel:
            cancelRecording(requestID: requestID, deadline: deadline)
        }
    }

    private func startRecording(requestID: UUID, deadline: Date) {
        guard recorder == nil,
              case .ready = presentation,
              UIApplication.shared.applicationState != .inactive else {
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("holdtype-kbd-probe-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            let recorder = try AVAudioRecorder(
                url: url,
                settings: [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 16_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey:
                        AVAudioQuality.medium.rawValue,
                ]
            )
            recorder.prepareToRecord()
            let remaining = max(0, deadline.timeIntervalSinceNow)
            guard remaining > 0,
                  recorder.record(forDuration: remaining),
                  recorder.isRecording else {
                try? FileManager.default.removeItem(at: url)
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                failAndStop("Recording unavailable")
                return
            }
            self.recorder = recorder
            recordingURL = url
            guard publish(
                phase: .listening,
                requestID: requestID,
                expiresAt: deadline
            ) else {
                failAndStop("Session unavailable")
                return
            }
            presentation = .listening(deadline)
        } catch {
            try? FileManager.default.removeItem(at: url)
            failAndStop("Recording unavailable")
        }
    }

    private func finishRecording(requestID: UUID, deadline: Date) {
        guard recorder?.isRecording == true else { return }
        stopAndDeleteRecording()
        guard recorder == nil else {
            failAndStop("Recording did not stop")
            return
        }
        guard publish(
            phase: .processing,
            requestID: requestID,
            expiresAt: deadline
        ) else {
            failAndStop("Session unavailable")
            return
        }
        presentation = .processing

        #if DEBUG
        let result = "HoldType keyboard device probe"
        guard publish(
            phase: .resultReady,
            requestID: requestID,
            result: result,
            expiresAt: deadline
        ) else {
            failAndStop("Session unavailable")
            return
        }
        #else
        failAndStop("Probe unavailable")
        #endif
    }

    private func cancelRecording(requestID: UUID, deadline: Date) {
        stopAndDeleteRecording()
        _ = publish(
            phase: .unavailable,
            requestID: requestID,
            expiresAt: deadline
        )
        finishSessionLifetime()
        presentation = .stopped
    }

    private func failAndStop(_ message: String) {
        if let requestID, let deadline, deadline > Date() {
            _ = publish(
                phase: .failed,
                requestID: requestID,
                expiresAt: deadline
            )
        }
        stopAndDeleteRecording()
        finishSessionLifetime()
        presentation = .failed(message)
    }

    private func stopSession(publishUnavailable: Bool) {
        stopAndDeleteRecording()
        if publishUnavailable,
           let requestID,
           let deadline,
           deadline > Date() {
            _ = publish(
                phase: .unavailable,
                requestID: requestID,
                expiresAt: deadline
            )
        }
        finishSessionLifetime()
        presentation = .stopped
    }

    private func expireSession() {
        guard let requestID else { return }
        stopAndDeleteRecording()
        let now = Date()
        _ = publish(
            phase: .unavailable,
            requestID: requestID,
            publishedAt: now,
            expiresAt: now.addingTimeInterval(1)
        )
        finishSessionLifetime()
        presentation = .stopped
    }

    private func stopAndDeleteRecording() {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
    }

    private func publish(
        phase: KeyboardDictationStatePhase,
        requestID: UUID,
        result: String? = nil,
        publishedAt: Date = Date(),
        expiresAt: Date
    ) -> Bool {
        guard let store,
              let record = KeyboardDictationStateRecord(
                requestID: requestID,
                phase: phase,
                result: result,
                publishedAt: publishedAt,
                expiresAt: expiresAt
              ),
              (try? store.saveState(record)) != nil else {
            return false
        }
        KeyboardDictationBridgeSignal.postStateChanged()
        return true
    }

    private func beginBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "Keyboard Dictation Session"
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.expireSession()
            }
        }
    }

    private func scheduleExpiry(at date: Date) {
        expiryTimer?.invalidate()
        let timer = Timer(fire: date, interval: 0, repeats: false) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.expireSession()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    private func finishSessionLifetime() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        requestID = nil
        deadline = nil
        lastHandledCommand = nil
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}
