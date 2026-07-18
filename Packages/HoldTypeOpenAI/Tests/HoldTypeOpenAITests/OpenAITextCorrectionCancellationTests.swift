import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypeOpenAI

struct OpenAITextCorrectionCancellationTests {
    @Test func timeoutMapsToTextCorrectionTimeout() async throws {
        let loader = CorrectionFakeURLLoader(
            result: .delayedSuccess(
                Data(#"{"output_text":"late"}"#.utf8),
                makeCorrectionHTTPResponse(statusCode: 200)
            )
        )
        let sleeper = CorrectionFakeTimeoutSleeper(mode: .timeoutImmediately)
        let service = makeService(loader: loader, sleeper: sleeper, requestTimeout: 2)
        let transcript = try AcceptedTranscript(rawText: "transcript")

        await expectCorrectionError(.timedOut) {
            try await service.correct(
                transcript,
                configuration: .defaults,
                credential: testCredential()
            )
        }

        #expect(loader.requests.count == 1)
        try await loader.waitForCancellationCount(1)
        #expect(loader.cancellationCount == 1)
        #expect(sleeper.sleepCalls == [2])
    }

    @Test func cancellationStopsTransportAndNextRequestSucceedsIndependently() async throws {
        let loader = CorrectionSequencedURLLoader(
            steps: [
                .waitForCancellation,
                .success(
                    Data(#"{"output_text":"fresh correction"}"#.utf8),
                    makeCorrectionHTTPResponse(statusCode: 200)
                ),
            ]
        )
        let service = makeService(loader: loader)
        let transcript = try AcceptedTranscript(rawText: "transcript")
        let credential = try testCredential()

        service.cancelActiveCorrection()
        let cancelledTask = Task {
            try await service.correct(
                transcript,
                configuration: .defaults,
                credential: credential
            )
        }
        try await loader.waitForRequestCount(1)

        service.cancelActiveCorrection()
        service.cancelActiveCorrection()

        await expectCorrectionError(.cancelled) {
            try await cancelledTask.value
        }
        try await loader.waitForCancellationCount(1)
        #expect(await loader.observedCancellationCount() == 1)

        let correction = try await service.correct(
            transcript,
            configuration: .defaults,
            credential: credential
        )
        #expect(correction == "fresh correction")

        service.cancelActiveCorrection()
    }

    @Test func cancellationCompletesBeforeNonCooperativeLoaderReturns() async throws {
        let loader = ControlledURLLoader(cancellationBehaviors: [.awaitResponse])
        let service = makeService(loader: loader)
        let transcript = try AcceptedTranscript(rawText: "transcript")
        let credential = try testCredential()
        let resultProbe = AsyncOperationResultProbe<String>()
        let lateResponse = makeCorrectionHTTPResponse(statusCode: 200)
        defer {
            loader.resolveRequest(
                at: 0,
                data: Data(#"{"output_text":"late correction"}"#.utf8),
                response: lateResponse
            )
        }

        let correction = Task {
            do {
                let result = try await service.correct(
                    transcript,
                    configuration: .defaults,
                    credential: credential
                )
                resultProbe.complete(with: .success(result))
            } catch {
                resultProbe.complete(with: .failure(error))
            }
        }
        try await loader.waitForRequestCount(1)

        service.cancelActiveCorrection()

        try await loader.waitForCancellation(ofRequestAt: 0)
        let result = try await resultProbe.waitForResult()
        switch result {
        case .success:
            Issue.record("Expected cancellation before the loader returned.")
        case let .failure(error as OpenAITextCorrectionServiceError):
            #expect(error == .cancelled)
        case let .failure(error):
            Issue.record("Expected OpenAITextCorrectionServiceError.cancelled, got \(error)")
        }
        await correction.value
    }

    @Test func lateCancelledResponseCannotPublishOrClearNewActiveRequest() async throws {
        let loader = CorrectionSequencedURLLoader(
            steps: [
                .lateSuccessAfterCancellation(
                    Data(#"{"output_text":"late correction"}"#.utf8),
                    makeCorrectionHTTPResponse(statusCode: 200)
                ),
                .waitForCancellation,
            ]
        )
        let service = makeService(loader: loader)
        let transcript = try AcceptedTranscript(rawText: "transcript")
        let credential = try testCredential()

        let oldTask = Task {
            try await service.correct(
                transcript,
                configuration: .defaults,
                credential: credential
            )
        }
        try await loader.waitForRequestCount(1)

        let newTask = Task {
            try await service.correct(
                transcript,
                configuration: .defaults,
                credential: credential
            )
        }
        try await loader.waitForRequestCount(2)

        await expectCorrectionError(.cancelled) {
            try await oldTask.value
        }

        service.cancelActiveCorrection()

        await expectCorrectionError(.cancelled) {
            try await newTask.value
        }
        try await loader.waitForCancellationCount(2)
        #expect(await loader.observedCancellationCount() == 2)
    }

    private func makeService(
        loader: any URLLoading,
        sleeper: CorrectionFakeTimeoutSleeper = CorrectionFakeTimeoutSleeper(),
        requestTimeout: TimeInterval = 5
    ) -> OpenAITextCorrectionService {
        OpenAITextCorrectionService(
            endpointURL: OpenAITextCorrectionService.defaultEndpointURL,
            urlLoader: loader,
            timeoutSleeper: sleeper,
            requestTimeout: requestTimeout
        )
    }

    private func testCredential(_ apiKey: String = "sk-test") throws -> OpenAICredential {
        try OpenAICredential(apiKey: apiKey)
    }
}
