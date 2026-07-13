#if DEBUG
import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypePersistence
import SwiftUI

/// Debug-only, side-effect-free rendered-state qualification entry points.
/// Release builds do not compile this file or its launch-environment contract.
nonisolated enum IOSUIQualificationRoute:
    String,
    CaseIterable,
    Equatable,
    Identifiable,
    Sendable {
    case gallery
    case voiceStart = "voice-start"
    case voiceSetupBlocked = "voice-setup-blocked"
    case voiceArming = "voice-arming"
    case voiceListening = "voice-listening"
    case voiceFinalizing = "voice-finalizing"
    case voiceProcessing = "voice-processing"
    case voicePostProcessing = "voice-post-processing"
    case voiceOutputDelivery = "voice-output-delivery"
    case voiceCaptureRecovery = "voice-capture-recovery"
    case voicePendingRetry = "voice-pending-retry"
    case latestEmpty = "latest-empty"
    case latestSuccess = "latest-success"
    case latestFailure = "latest-failure"
    case privacyChecking = "privacy-checking"
    case privacyReady = "privacy-ready"
    case privacyAccepted = "privacy-accepted"
    case privacyUnreadable = "privacy-unreadable"
    case privacyFailure = "privacy-failure"
    case usageEmpty = "usage-empty"
    case usageKnown = "usage-known"
    case usageMixed = "usage-mixed"
    case usageUnknown = "usage-unknown"
    case usageLoadFailure = "usage-load-failure"
    case usageWriteWarning = "usage-write-warning"
    case usageResetFailure = "usage-reset-failure"

    static let environmentKey = "HOLDTYPE_UI_QUALIFICATION"

    static var current: Self? {
        resolve(environment: ProcessInfo.processInfo.environment)
    }

    static func resolve(environment: [String: String]) -> Self? {
        guard let rawValue = environment[environmentKey] else { return nil }
        return Self(rawValue: rawValue)
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gallery:
            "Qualification Gallery"
        case .voiceStart:
            "Voice — Start and Translate"
        case .voiceSetupBlocked:
            "Voice — Setup Blocked"
        case .voiceArming:
            "Voice — Arming"
        case .voiceListening:
            "Voice — Listening"
        case .voiceFinalizing:
            "Voice — Finalizing"
        case .voiceProcessing:
            "Voice — Processing"
        case .voicePostProcessing:
            "Voice — Refining Text"
        case .voiceOutputDelivery:
            "Voice — Publishing Result"
        case .voiceCaptureRecovery:
            "Voice — Recover or Discard"
        case .voicePendingRetry:
            "Voice — Retry or Discard"
        case .latestEmpty:
            "Latest Result — Empty"
        case .latestSuccess:
            "Latest Result — Success and Actions"
        case .latestFailure:
            "Latest Result — Failure"
        case .privacyChecking:
            "Privacy — Checking"
        case .privacyReady:
            "Privacy — Ready and Consent Review"
        case .privacyAccepted:
            "Privacy — Accepted and Withdraw Confirmation"
        case .privacyUnreadable:
            "Privacy — Unreadable Data Reset Confirmation"
        case .privacyFailure:
            "Privacy — Local Data Failure"
        case .usageEmpty:
            "Usage — Empty"
        case .usageKnown:
            "Usage — Known Pricing"
        case .usageMixed:
            "Usage — Mixed Pricing"
        case .usageUnknown:
            "Usage — Unknown Pricing"
        case .usageLoadFailure:
            "Usage — Local Read Failure"
        case .usageWriteWarning:
            "Usage — Incomplete Estimate Warning"
        case .usageResetFailure:
            "Usage — Reset Failure"
        }
    }

    fileprivate var section: IOSUIQualificationSection? {
        switch self {
        case .gallery:
            nil
        case .voiceStart, .voiceSetupBlocked, .voiceArming, .voiceListening,
             .voiceFinalizing, .voiceProcessing, .voicePostProcessing,
             .voiceOutputDelivery, .voiceCaptureRecovery, .voicePendingRetry:
            .voice
        case .latestEmpty, .latestSuccess, .latestFailure:
            .latestResult
        case .privacyChecking, .privacyReady, .privacyAccepted,
             .privacyUnreadable, .privacyFailure:
            .privacy
        case .usageEmpty, .usageKnown, .usageMixed, .usageUnknown,
             .usageLoadFailure, .usageWriteWarning, .usageResetFailure:
            .usage
        }
    }

    fileprivate var voiceScenario: IOSUIQualificationVoiceScenario? {
        switch self {
        case .voiceStart:
            .start
        case .voiceSetupBlocked:
            .setupBlocked
        case .voiceArming:
            .arming
        case .voiceListening:
            .listening
        case .voiceFinalizing:
            .finalizing
        case .voiceProcessing:
            .processing
        case .voicePostProcessing:
            .postProcessing
        case .voiceOutputDelivery:
            .outputDelivery
        case .voiceCaptureRecovery:
            .captureRecovery
        case .voicePendingRetry:
            .pendingRetry
        case .latestEmpty:
            .latestEmpty
        case .latestSuccess:
            .latestSuccess
        case .latestFailure:
            .latestFailure
        case .gallery, .privacyChecking, .privacyReady, .privacyAccepted,
             .privacyUnreadable, .privacyFailure, .usageEmpty,
             .usageKnown, .usageMixed, .usageUnknown, .usageLoadFailure,
             .usageWriteWarning, .usageResetFailure:
            nil
        }
    }

    fileprivate var privacyScenario: IOSUIQualificationPrivacyScenario? {
        switch self {
        case .privacyChecking:
            .checking
        case .privacyReady:
            .ready
        case .privacyAccepted:
            .accepted
        case .privacyUnreadable:
            .unreadable
        case .privacyFailure:
            .failure
        case .gallery, .voiceStart, .voiceSetupBlocked, .voiceArming,
             .voiceListening, .voiceFinalizing, .voiceProcessing,
             .voicePostProcessing, .voiceOutputDelivery,
             .voiceCaptureRecovery, .voicePendingRetry, .latestEmpty,
             .latestSuccess, .latestFailure, .usageEmpty, .usageKnown,
             .usageMixed, .usageUnknown, .usageLoadFailure,
             .usageWriteWarning, .usageResetFailure:
            nil
        }
    }

    var usageScenario: IOSUIQualificationUsageScenario? {
        switch self {
        case .usageEmpty:
            .empty
        case .usageKnown:
            .known
        case .usageMixed:
            .mixed
        case .usageUnknown:
            .unknown
        case .usageLoadFailure:
            .loadFailure
        case .usageWriteWarning:
            .writeWarning
        case .usageResetFailure:
            .resetFailure
        case .gallery, .voiceStart, .voiceSetupBlocked, .voiceArming,
             .voiceListening, .voiceFinalizing, .voiceProcessing,
             .voicePostProcessing, .voiceOutputDelivery,
             .voiceCaptureRecovery, .voicePendingRetry, .latestEmpty,
             .latestSuccess, .latestFailure, .privacyChecking,
             .privacyReady, .privacyAccepted, .privacyUnreadable,
             .privacyFailure:
            nil
        }
    }
}

fileprivate nonisolated enum IOSUIQualificationSection:
    String,
    CaseIterable,
    Hashable {
    case voice = "Voice"
    case latestResult = "Latest Result"
    case privacy = "Privacy & Permissions"
    case usage = "Usage Estimate"
}

struct IOSUIQualificationRootView: View {
    let route: IOSUIQualificationRoute

    var body: some View {
        if route == .gallery {
            gallery
        } else {
            destination(route)
        }
    }

    private var gallery: some View {
        NavigationStack {
            List {
                ForEach(IOSUIQualificationSection.allCases, id: \.self) {
                    section in
                    Section(section.rawValue) {
                        ForEach(routes(in: section)) { route in
                            NavigationLink(route.title) {
                                destination(route)
                            }
                            .accessibilityIdentifier(
                                "ios.qualification.route.\(route.rawValue)"
                            )
                        }
                    }
                }
            }
            .navigationTitle(route.title)
            .accessibilityIdentifier("ios.qualification.gallery")
        }
    }

    @ViewBuilder
    private func destination(_ route: IOSUIQualificationRoute) -> some View {
        if let scenario = route.voiceScenario {
            IOSUIQualificationVoiceHost(scenario: scenario)
        } else if let scenario = route.privacyScenario {
            IOSUIQualificationPrivacyHost(scenario: scenario)
        } else if let scenario = route.usageScenario {
            IOSUIQualificationUsageHost(scenario: scenario)
        } else {
            ContentUnavailableView(
                "Qualification Route Unavailable",
                systemImage: "exclamationmark.triangle"
            )
        }
    }

    private func routes(
        in section: IOSUIQualificationSection
    ) -> [IOSUIQualificationRoute] {
        IOSUIQualificationRoute.allCases.filter { $0.section == section }
    }
}

fileprivate enum IOSUIQualificationVoiceScenario: Sendable {
    case start
    case setupBlocked
    case arming
    case listening
    case finalizing
    case processing
    case postProcessing
    case outputDelivery
    case captureRecovery
    case pendingRetry
    case latestEmpty
    case latestSuccess
    case latestFailure

    var observation: IOSForegroundVoiceObservation {
        IOSForegroundVoiceObservation(
            setup: setup,
            recovery: recovery,
            stage: recoveryStage,
            latestAvailability: latestAvailability,
            translationAvailable: true
        )
    }

    var setup: IOSForegroundVoiceSetup {
        switch self {
        case .setupBlocked:
            .needsSetup(.openAI)
        case .start, .arming, .listening, .finalizing, .processing,
             .postProcessing, .outputDelivery, .captureRecovery,
             .pendingRetry, .latestEmpty, .latestSuccess, .latestFailure:
            .ready
        }
    }

    var recovery: IOSForegroundVoiceRecovery {
        switch self {
        case .captureRecovery:
            .captureRecoverOrDiscard
        case .pendingRetry:
            .pendingRetryOrDiscard
        case .start, .setupBlocked, .arming, .listening, .finalizing,
             .processing, .postProcessing, .outputDelivery, .latestEmpty,
             .latestSuccess, .latestFailure:
            .none
        }
    }

    var recoveryStage: VoiceAttemptStage? {
        switch self {
        case .captureRecovery:
            .recordingFinalization
        case .pendingRetry:
            .transcription
        case .start, .setupBlocked, .arming, .listening, .finalizing,
             .processing, .postProcessing, .outputDelivery, .latestEmpty,
             .latestSuccess, .latestFailure:
            nil
        }
    }

    var latestAvailability: IOSForegroundVoiceLatestAvailability {
        switch self {
        case .latestSuccess:
            .available
        case .latestFailure:
            .unavailable
        case .start, .setupBlocked, .arming, .listening, .finalizing,
             .processing, .postProcessing, .outputDelivery, .captureRecovery,
             .pendingRetry, .latestEmpty:
            .absent
        }
    }

    var progress: [IOSForegroundVoiceProgress] {
        switch self {
        case .arming:
            []
        case .listening:
            [.listening]
        case .finalizing:
            [.listening, .finalizing]
        case .processing:
            [.listening, .finalizing, .processing(.transcription)]
        case .postProcessing:
            [.listening, .finalizing, .processing(.postProcessing)]
        case .outputDelivery:
            [.listening, .finalizing, .processing(.outputDelivery)]
        case .start, .setupBlocked, .captureRecovery, .pendingRetry,
             .latestEmpty, .latestSuccess, .latestFailure:
            []
        }
    }

    var startsOperation: Bool {
        switch self {
        case .arming, .listening, .finalizing, .processing,
             .postProcessing, .outputDelivery:
            true
        case .start, .setupBlocked, .captureRecovery, .pendingRetry,
             .latestEmpty, .latestSuccess, .latestFailure:
            false
        }
    }

    var latestResult: IOSUIQualificationLatestResult {
        switch self {
        case .latestSuccess:
            .success
        case .latestFailure:
            .failure
        case .start, .setupBlocked, .arming, .listening, .finalizing,
             .processing, .postProcessing, .outputDelivery, .captureRecovery,
             .pendingRetry, .latestEmpty:
            .empty
        }
    }
}

private nonisolated enum IOSUIQualificationLatestResult: Sendable {
    case empty
    case success
    case failure
}

@MainActor
private final class IOSUIQualificationVoiceFixture {
    let sceneOwner: IOSForegroundVoiceSceneHostOwner
    let latestResultOwner: IOSForegroundVoiceLatestResultOwner
    let consentOwner: IOSProviderConsentPresentationOwner

    private let controller: IOSForegroundVoiceController
    private let scenario: IOSUIQualificationVoiceScenario
    private var isPrepared = false

    init(scenario: IOSUIQualificationVoiceScenario) {
        self.scenario = scenario
        let observation = scenario.observation
        let progressSteps = scenario.progress
        let client = IOSForegroundVoiceClient(
            observe: { observation },
            runStart: { _, _, _, progress in
                for step in progressSteps {
                    await progress(step)
                }
                await IOSUIQualificationSuspension.hold()
                return IOSForegroundVoiceResolution(
                    observation: observation
                )
            },
            run: { _, _, progress in
                for step in progressSteps {
                    await progress(step)
                }
                await IOSUIQualificationSuspension.hold()
                return IOSForegroundVoiceResolution(
                    observation: observation
                )
            },
            finishUtterance: { _ in .accepted }
        )
        let registry = IOSVoiceSceneRegistry()
        let controller = IOSForegroundVoiceController(
            client: client,
            sceneRegistry: registry
        )
        self.controller = controller
        sceneOwner = IOSForegroundVoiceSceneHostOwner(
            controller: controller,
            sceneRegistry: registry
        )

        let latestResult = scenario.latestResult
        latestResultOwner = IOSForegroundVoiceLatestResultOwner(
            load: {
                switch latestResult {
                case .empty:
                    return .absent
                case .success:
                    return .resultReady(
                        try IOSV1AcceptedOutputDeliveryRecord(
                            resultID: UUID(),
                            sourceAttemptID: UUID(),
                            acceptedText: "A protected sample dictation result "
                                + "for layout and action qualification.",
                            createdAt: Date()
                        )
                    )
                case .failure:
                    throw IOSUIQualificationFailure.latestResultUnavailable
                }
            },
            clear: { _ in .alreadyAbsent }
        )
        consentOwner = IOSUIQualificationConsentFixture.makeOwner(
            sceneRegistry: registry,
            scenario: .ready
        )
    }

    func prepare() async {
        guard !isPrepared else { return }
        isPrepared = true
        _ = sceneOwner.register(initialActivity: .active)
        await controller.activate()
        do {
            _ = try await latestResultOwner.loadForVoiceWorkflow()
        } catch {
            // The failure route intentionally renders the owner's fail-closed
            // presentation; no external work or retry follows this error.
        }

        guard scenario.startsOperation,
              let command = sceneOwner.actionCommands.first(where: {
                  $0.action == .startStandard
              }) else {
            return
        }
        _ = sceneOwner.submit(command)
        await Task.yield()
    }
}

private struct IOSUIQualificationVoiceHost: View {
    @State private var fixture: IOSUIQualificationVoiceFixture
    @State private var practiceText = ""

    init(scenario: IOSUIQualificationVoiceScenario) {
        _fixture = State(
            initialValue: IOSUIQualificationVoiceFixture(scenario: scenario)
        )
    }

    var body: some View {
        NavigationStack {
            IOSVoiceHomeView(
                practiceText: $practiceText,
                secureProviderAvailability: .available,
                openSettings: { _ in }
            )
            .environment(fixture.sceneOwner)
            .environment(fixture.latestResultOwner)
            .environment(fixture.consentOwner)
        }
        .task {
            await fixture.prepare()
        }
        .environment(\.showsKeyboardBridgeProbe, false)
        .accessibilityIdentifier("ios.qualification.voice")
    }
}

fileprivate nonisolated enum IOSUIQualificationPrivacyScenario:
    Equatable,
    Sendable {
    case checking
    case ready
    case accepted
    case unreadable
    case failure

    var microphoneStatus: IOSMicrophonePermissionStatus {
        switch self {
        case .checking:
            .unavailable
        case .ready, .accepted, .unreadable:
            .undetermined
        case .failure:
            .unavailable
        }
    }
}

private struct IOSUIQualificationPrivacyHost: View {
    @State private var consentOwner: IOSProviderConsentPresentationOwner

    init(scenario: IOSUIQualificationPrivacyScenario) {
        let registry = IOSVoiceSceneRegistry()
        _consentOwner = State(
            initialValue: IOSUIQualificationConsentFixture.makeOwner(
                sceneRegistry: registry,
                scenario: scenario
            )
        )
    }

    var body: some View {
        NavigationStack {
            IOSPrivacyPermissionsView()
                .environment(consentOwner)
        }
        .accessibilityIdentifier("ios.qualification.privacy")
    }
}

private enum IOSUIQualificationConsentFixture {
    @MainActor
    static func makeOwner(
        sceneRegistry: IOSVoiceSceneRegistry,
        scenario: IOSUIQualificationPrivacyScenario
    ) -> IOSProviderConsentPresentationOwner {
        let client = IOSProviderConsentPresentationClient(
            observe: {
                if scenario == .checking {
                    do {
                        try await Task.sleep(for: .seconds(60))
                    } catch {
                        return IOSV1ProviderConsentQualificationFixture
                            .notReviewedObservation()
                    }
                }
                switch scenario {
                case .checking, .ready:
                    return IOSV1ProviderConsentQualificationFixture
                        .notReviewedObservation()
                case .accepted:
                    return IOSV1ProviderConsentQualificationFixture
                        .acceptedObservation()
                case .unreadable:
                    return IOSV1ProviderConsentQualificationFixture
                        .resettableUnreadableObservation()
                case .failure:
                    return IOSV1ProviderConsentQualificationFixture
                        .localDataUnavailableObservation()
                }
            },
            accept: { _, _ in
                throw IOSUIQualificationFailure.mutationBlocked
            },
            withdraw: { _, _, _ in
                throw IOSUIQualificationFailure.mutationBlocked
            },
            resetUnreadableData: { _, _ in
                throw IOSUIQualificationFailure.mutationBlocked
            },
            isAuthorizationReady: { observation in
                IOSV1ProviderConsentQualificationFixture
                    .isAuthorizationReady(for: observation)
            },
            hasSameObservationAuthority: { candidate, current in
                IOSV1ProviderConsentQualificationFixture
                    .hasSameObservationAuthority(
                    candidate,
                    as: current
                )
            }
        )
        return IOSProviderConsentPresentationOwner(
            client: client,
            sceneRegistry: sceneRegistry,
            readMicrophoneStatus: { scenario.microphoneStatus }
        )
    }
}

nonisolated enum IOSUIQualificationUsageScenario:
    Equatable,
    Sendable {
    case empty
    case known
    case mixed
    case unknown
    case loadFailure
    case writeWarning
    case resetFailure

    static let now = Date(timeIntervalSince1970: 1_784_117_600)

    var events: [TranscriptionUsageEvent] {
        switch self {
        case .empty, .loadFailure:
            []
        case .known, .writeWarning, .resetFailure:
            Self.makeEvents(models: [
                (0, "gpt-4o-transcribe", 90),
                (-2, "gpt-4o-mini-transcribe", 150),
                (-7, "gpt-4o-transcribe", 300),
                (-20, "gpt-4o-mini-transcribe", 75),
            ])
        case .mixed:
            Self.makeEvents(models: [
                (0, "gpt-4o-transcribe", 90),
                (0, "future-transcribe-model", 120),
                (-2, "gpt-4o-mini-transcribe", 150),
                (-7, "future-transcribe-model", 300),
            ])
        case .unknown:
            Self.makeEvents(models: [
                (0, "future-transcribe-model", 120),
                (-2, "another-future-model", 150),
                (-7, "future-transcribe-model", 300),
            ])
        }
    }

    var hasLoadFailure: Bool { self == .loadFailure }
    var hasWriteWarning: Bool { self == .writeWarning }
    var hasResetFailure: Bool { self == .resetFailure }

    var summary: TranscriptionUsageSummary {
        TranscriptionUsageSummary.make(
            events: events,
            now: Self.now,
            calendar: Self.calendar
        )
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private static func makeEvents(
        models: [(dayOffset: Int, model: String, duration: TimeInterval)]
    ) -> [TranscriptionUsageEvent] {
        models.enumerated().map { index, fixture in
            let timestamp = calendar.date(
                byAdding: .day,
                value: fixture.dayOffset,
                to: now
            ) ?? now
            do {
                return try TranscriptionUsagePricing.current.makeEvent(
                    timestamp: timestamp,
                    model: fixture.model,
                    durationSeconds: fixture.duration,
                    id: qualificationIdentifier(index: index)
                )
            } catch {
                fatalError("Invalid usage qualification fixture: \(error)")
            }
        }
    }

    private static func qualificationIdentifier(index: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "E0000000-0000-0000-0000-%012X",
                index + 1
            )
        ) ?? UUID()
    }
}

private struct IOSUIQualificationUsageHost: View {
    @State private var stateOwner: IOSUsageEstimateStateOwner
    private let scenario: IOSUIQualificationUsageScenario

    init(scenario: IOSUIQualificationUsageScenario) {
        self.scenario = scenario
        let owner = IOSUsageEstimateStateOwner(
            client: IOSUsageEstimateClient(
                load: {
                    if scenario.hasLoadFailure {
                        throw IOSUIQualificationFailure.usageLoadUnavailable
                    }
                    return scenario.events
                },
                reset: {
                    if scenario.hasResetFailure {
                        throw IOSUIQualificationFailure.usageResetUnavailable
                    }
                    return IOSTranscriptionUsageQualificationFixture
                        .writeToken(revision: 2)
                }
            ),
            calendar: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
                return calendar
            }(),
            now: { IOSUIQualificationUsageScenario.now }
        )
        if scenario.hasWriteWarning {
            owner.reportWriteFailure(
                IOSTranscriptionUsageQualificationFixture
                    .writeToken(revision: 1)
            )
        }
        _stateOwner = State(initialValue: owner)
    }

    var body: some View {
        NavigationStack {
            IOSUsageEstimateView()
                .environment(stateOwner)
        }
        .task(id: stateOwner.summary) {
            guard scenario.hasResetFailure,
                  stateOwner.summary?.isEmpty == false,
                  stateOwner.operation == .idle else {
                return
            }
            _ = await stateOwner.reset()
        }
        .accessibilityIdentifier("ios.qualification.usage")
    }
}

private enum IOSUIQualificationSuspension {
    static func hold() async {
        do {
            try await Task.sleep(for: .seconds(86_400))
        } catch {
            // Cancellation is the intended release path for a rendered state.
        }
    }
}

private nonisolated enum IOSUIQualificationFailure: Error {
    case latestResultUnavailable
    case mutationBlocked
    case usageLoadUnavailable
    case usageResetUnavailable
}
#endif
