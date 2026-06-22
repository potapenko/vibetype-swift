//
//  DictationSessionController.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

import Foundation

protocol TranscriptOutputDelivering {
    func deliver(_ transcript: String, settings: AppSettings) async throws -> TextInsertionResult
}

extension TextInsertionService: TranscriptOutputDelivering {}

@MainActor
final class DictationSessionController {
    private let recorder: any AudioRecorderService
    private let transcriptionService: any OpenAITranscriptionServing
    private let settingsProvider: () -> AppSettings
    private let transcriptOutput: any TranscriptOutputDelivering
    private let cuePlayer: any DictationCuePlaying
    private let transcriptHistory: any TranscriptRecoveryHistoryRecording
    private let activeTextContextReader: any ActiveTextContextReading

    private var isPerformingAction = false
    private var nextSessionID = 0
    private var activeSessionID: Int?

    private(set) var status: DictationStatus
    private(set) var lastTranscriptText: String?
    private(set) var outputStatusText: String?

    init(
        recorder: any AudioRecorderService = AVFoundationAudioRecorderService(),
        transcriptionService: any OpenAITranscriptionServing = OpenAITranscriptionService(),
        settingsProvider: @escaping () -> AppSettings = { AppSettingsStore().load() },
        transcriptOutput: any TranscriptOutputDelivering = TextInsertionService(),
        cuePlayer: any DictationCuePlaying = NativeDictationCuePlayer.shared,
        transcriptHistory: (any TranscriptRecoveryHistoryRecording)? = nil,
        activeTextContextReader: any ActiveTextContextReading = ActiveTextContextService(),
        initialStatus: DictationStatus = .idle,
        lastTranscriptText: String? = nil,
        outputStatusText: String? = nil
    ) {
        self.recorder = recorder
        self.transcriptionService = transcriptionService
        self.settingsProvider = settingsProvider
        self.transcriptOutput = transcriptOutput
        self.cuePlayer = cuePlayer
        self.transcriptHistory = transcriptHistory ?? TranscriptRecoveryHistoryStore.shared
        self.activeTextContextReader = activeTextContextReader
        self.status = initialStatus
        self.lastTranscriptText = lastTranscriptText.flatMap {
            AcceptedTranscript.nonEmptyNormalizedText(from: $0)
        }
            ?? initialStatus.lastTranscriptText
        self.outputStatusText = outputStatusText
    }

    func performRecordingAction() async {
        guard !isPerformingAction else {
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        switch status {
        case .idle, .success, .failure:
            await startRecording()
        case .recording:
            await stopRecordingAndTranscribe()
        case .transcribing:
            return
        }
    }

    func cancelRecording() {
        switch status {
        case .recording:
            guard !isPerformingAction else {
                return
            }

            recorder.cancelRecording()
            cancelActiveSession()
            outputStatusText = nil

            switch recorder.currentStatus {
            case .failed(let message):
                status = .failure(message: message)
            default:
                status = .idle
            }
        case .transcribing:
            transcriptionService.cancelActiveTranscription()
            cancelActiveSession()
            outputStatusText = nil
            status = .idle
        default:
            return
        }
    }

    private func beginSession() -> Int {
        nextSessionID += 1
        activeSessionID = nextSessionID
        return nextSessionID
    }

    private func currentOrNewSessionID() -> Int {
        if let activeSessionID {
            return activeSessionID
        }

        return beginSession()
    }

    private func isCurrentSession(_ sessionID: Int) -> Bool {
        activeSessionID == sessionID
    }

    private func finishSession(_ sessionID: Int) {
        guard activeSessionID == sessionID else {
            return
        }

        activeSessionID = nil
    }

    private func cancelActiveSession() {
        activeSessionID = nil
    }

    private func startRecording() async {
        outputStatusText = nil
        let settings = settingsProvider()
        let sessionID = beginSession()

        do {
            try await recorder.startRecording()
            guard isCurrentSession(sessionID) else {
                return
            }

            status = .recording
            playCue(.startRecording, settings: settings)
        } catch {
            finishSession(sessionID)
            status = .failure(message: Self.userFacingMessage(for: error))
        }
    }

    private func stopRecordingAndTranscribe() async {
        outputStatusText = nil
        let sessionID = currentOrNewSessionID()

        do {
            let artifact = try await recorder.stopRecording()
            guard isCurrentSession(sessionID) else {
                return
            }

            let settings = settingsProvider()
            playCue(.stopRecording, settings: settings)
            status = .transcribing

            let context = activeTextContextReader.currentContext(settings: settings)
            let rawTranscript = try await transcriptionService.transcribe(
                audioFileURL: artifact.fileURL,
                settings: settings,
                context: context
            )
            guard isCurrentSession(sessionID) else {
                return
            }

            let acceptedTranscript = try Self.acceptedTranscript(from: rawTranscript)
            lastTranscriptText = acceptedTranscript.text
            status = .success(transcript: acceptedTranscript.text)
            recordRecoveryHistory(
                acceptedTranscript.text,
                settings: settings,
                audioDuration: artifact.duration
            )

            do {
                outputStatusText = try await transcriptOutput.deliver(
                    acceptedTranscript.text,
                    settings: settings
                ).statusText
            } catch {
                guard isCurrentSession(sessionID) else {
                    return
                }

                outputStatusText = Self.userFacingMessage(for: error)
            }

            finishSession(sessionID)
        } catch {
            guard isCurrentSession(sessionID) else {
                return
            }

            finishSession(sessionID)
            status = .failure(message: Self.userFacingMessage(for: error))
        }
    }

    private func playCue(_ cue: DictationCue, settings: AppSettings) {
        guard settings.soundEnabled else {
            return
        }

        cuePlayer.play(cue)
    }

    private func recordRecoveryHistory(
        _ transcript: String,
        settings: AppSettings,
        audioDuration: TimeInterval?
    ) {
        do {
            try transcriptHistory.recordAcceptedTranscript(
                transcript,
                settings: settings,
                audioDuration: audioDuration
            )
        } catch {
            outputStatusText = Self.userFacingMessage(for: error)
        }
    }

    private static func acceptedTranscript(from rawText: String) throws -> AcceptedTranscript {
        do {
            return try AcceptedTranscript(rawText: rawText)
        } catch AcceptedTranscript.ValidationError.emptyText {
            throw OpenAITranscriptionServiceError.emptyTranscript
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return description
        }

        return error.localizedDescription
    }
}
