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

    private var isPerformingAction = false

    private(set) var status: DictationStatus
    private(set) var lastTranscriptText: String?
    private(set) var outputStatusText: String?

    init(
        recorder: any AudioRecorderService = AVFoundationAudioRecorderService(),
        transcriptionService: any OpenAITranscriptionServing = OpenAITranscriptionService(),
        settingsProvider: @escaping () -> AppSettings = { AppSettingsStore().load() },
        transcriptOutput: any TranscriptOutputDelivering = TextInsertionService(),
        initialStatus: DictationStatus = .idle,
        lastTranscriptText: String? = nil,
        outputStatusText: String? = nil
    ) {
        self.recorder = recorder
        self.transcriptionService = transcriptionService
        self.settingsProvider = settingsProvider
        self.transcriptOutput = transcriptOutput
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
        guard !isPerformingAction, status == .recording else {
            return
        }

        recorder.cancelRecording()
        outputStatusText = nil

        switch recorder.currentStatus {
        case .failed(let message):
            status = .failure(message: message)
        default:
            status = .idle
        }
    }

    private func startRecording() async {
        outputStatusText = nil

        do {
            try await recorder.startRecording()
            status = .recording
        } catch {
            status = .failure(message: Self.userFacingMessage(for: error))
        }
    }

    private func stopRecordingAndTranscribe() async {
        outputStatusText = nil

        do {
            let artifact = try await recorder.stopRecording()
            let settings = settingsProvider()
            status = .transcribing

            let rawTranscript = try await transcriptionService.transcribe(
                audioFileURL: artifact.fileURL,
                settings: settings
            )
            let acceptedTranscript = try Self.acceptedTranscript(from: rawTranscript)
            lastTranscriptText = acceptedTranscript.text
            status = .success(transcript: acceptedTranscript.text)

            do {
                outputStatusText = try await transcriptOutput.deliver(
                    acceptedTranscript.text,
                    settings: settings
                ).statusText
            } catch {
                outputStatusText = Self.userFacingMessage(for: error)
            }
        } catch {
            status = .failure(message: Self.userFacingMessage(for: error))
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
