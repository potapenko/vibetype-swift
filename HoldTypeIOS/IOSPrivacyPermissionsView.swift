import Foundation
import HoldTypePersistence
import SwiftUI
import UIKit

struct IOSPrivacyPermissionsView: View {
    @Environment(IOSProviderConsentPresentationOwner.self)
    private var consentOwner
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingConfirmation:
        IOSPrivacyConsentConfirmation?
    @State private var disclosureReview:
        IOSPrivacyConsentConfirmation?
    @State private var accessibilityAnnouncementTask: Task<Void, Never>?
    @State private var accessibilityAnnouncementCandidate:
        IOSAccessibilityAnnouncementCandidate?

    var body: some View {
        List {
            microphoneSection
            providerConsentSection
            dataBoundarySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Privacy & Permissions")
        .accessibilityIdentifier("ios.privacy-permissions")
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await consentOwner.activatePrivacy() }
        }
        .onChange(of: consentOwner.confirmationRevision) { _, _ in
            if let pendingConfirmation,
               !consentOwner.isPrivacyConfirmationCurrent(
                   pendingConfirmation.token
               ) {
                self.pendingConfirmation = nil
            }
            if let disclosureReview,
               !consentOwner.isPrivacyConfirmationCurrent(
                   disclosureReview.token
               ) {
                self.disclosureReview = nil
            }
        }
        .onChange(of: consentOwner.privacyState) { _, state in
            guard case .ready(let snapshot) = state else { return }
            let presentation = IOSConsentPrivacyPresentation.resolve(snapshot)
            scheduleAccessibilityAnnouncement(
                IOSAccessibilityAnnouncement.message(
                    title: presentation.title,
                    detail: presentation.detail
                ),
                priority: .status
            )
        }
        .onChange(of: consentOwner.failure) { _, failure in
            guard let failure else { return }
            scheduleAccessibilityAnnouncement(
                IOSAccessibilityAnnouncement.message(
                    title: "Consent action failed",
                    detail: failure.detail
                ),
                priority: .content
            )
        }
        .onChange(of: consentOwner.notice) { _, notice in
            guard let notice else { return }
            scheduleAccessibilityAnnouncement(
                notice.title,
                priority: .content
            )
        }
        .onDisappear {
            accessibilityAnnouncementTask?.cancel()
            accessibilityAnnouncementTask = nil
            accessibilityAnnouncementCandidate = nil
        }
        .sheet(item: $disclosureReview) { confirmation in
            IOSProviderConsentPrivacyReviewSheet(
                confirmation: confirmation,
                consentOwner: consentOwner
            )
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingConfirmationIsCurrent },
                set: { if !$0 { pendingConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingConfirmation {
                Button(
                    pendingConfirmation.action.confirmationButtonTitle,
                    role: pendingConfirmation.action.confirmationRole
                ) {
                    _ = consentOwner.confirmPrivacyAction(
                        pendingConfirmation.token
                    )
                    self.pendingConfirmation = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingConfirmation = nil
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var microphoneSection: some View {
        let presentation = IOSMicrophonePrivacyPresentation.resolve(
            consentOwner.microphoneStatus
        )

        return Section("Microphone") {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                    Text(presentation.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: presentation.systemImage)
                    .foregroundStyle(presentation.color)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ios.privacy.microphone-status")

            if consentOwner.microphoneStatus == .denied,
               let settingsURL = URL(
                   string: UIApplication.openSettingsURLString
               ) {
                Link(destination: settingsURL) {
                    Label(
                        "Open System Settings",
                        systemImage: "arrow.up.forward.app"
                    )
                }
                .accessibilityIdentifier(
                    "ios.privacy.microphone-open-settings"
                )
            }
        }
    }

    @ViewBuilder
    private var providerConsentSection: some View {
        Section("OpenAI Processing Consent") {
            switch consentOwner.privacyState {
            case .notLoaded, .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Reading consent status…")
                    Spacer()
                }
                .accessibilityElement(children: .combine)
            case .ready(let snapshot):
                let presentation = IOSConsentPrivacyPresentation.resolve(
                    snapshot
                )
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(presentation.title)
                        Text(presentation.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let decisionAt = snapshot.decisionAt {
                            Text(
                                decisionAt.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: presentation.systemImage)
                        .foregroundStyle(presentation.color)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ios.privacy.consent-status")

                if let action = presentation.action {
                    Button(
                        action.buttonTitle,
                        role: action.buttonRole
                    ) {
                        if action == .acceptCurrentDisclosure {
                            beginDisclosureReview()
                        } else {
                            beginConfirmation(action)
                        }
                    }
                    .disabled(consentOwner.isBusy)
                    .accessibilityIdentifier(
                        "ios.privacy.consent.\(action.accessibilityName)"
                    )
                }

                if snapshot.canResetUnreadableData {
                    Button(
                        "Reset Unreadable Consent Data",
                        role: .destructive
                    ) {
                        beginConfirmation(.resetUnreadableData)
                    }
                    .disabled(consentOwner.isBusy)
                    .accessibilityIdentifier(
                        "ios.privacy.consent.reset-unreadable"
                    )
                }
            }

            if consentOwner.isBusy {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(consentOwner.operation.progressTitle)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
            }

            if let notice = consentOwner.notice {
                Label {
                    Text(notice.title)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                    .accessibilityIdentifier("ios.privacy.consent.notice")
            }

            if let failure = consentOwner.failure {
                Label {
                    Text(failure.detail)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ios.privacy.consent.failure")
            }
        }
    }

    private var dataBoundarySection: some View {
        Section("Data Boundaries") {
            privacyBoundary(
                "Save History is on by default and keeps up to 20 successful "
                    + "texts in protected app-private storage. It stores no "
                    + "audio or failed attempts.",
                image: "clock"
            )
            privacyBoundary(
                "The keyboard extension does not receive your API key, "
                    + "recordings, prompts, or History. Without Full Access, "
                    + "it can read one app-written Latest Result from the "
                    + "local shared container for explicit insertion. "
                    + "Insertion eligibility expires after 10 minutes; the "
                    + "next app publication removes the shared text.",
                image: "keyboard"
            )
            privacyBoundary(
                "Withdrawing consent closes OpenAI provider authority before "
                    + "the decision is written to local storage.",
                image: "lock.shield"
            )
            privacyBoundary(
                "Consent changes do not delete settings, History, Latest "
                    + "Result, usage, or your API key.",
                image: "externaldrive"
            )
        }
    }

    private var confirmationTitle: String {
        pendingConfirmation?.action.confirmationTitle ?? "Confirm Change"
    }

    private var pendingConfirmationIsCurrent: Bool {
        guard let pendingConfirmation else { return false }
        return consentOwner.isPrivacyConfirmationCurrent(
            pendingConfirmation.token
        )
    }

    private var confirmationMessage: String {
        pendingConfirmation?.action.confirmationMessage ?? ""
    }

    private func beginConfirmation(
        _ action: IOSProviderConsentPrivacyAction
    ) {
        guard let token = consentOwner.makePrivacyConfirmation(
            for: action
        ) else {
            return
        }
        pendingConfirmation = IOSPrivacyConsentConfirmation(
            token: token,
            action: action
        )
    }

    private func beginDisclosureReview() {
        guard let token = consentOwner.makePrivacyConfirmation(
            for: .acceptCurrentDisclosure
        ) else {
            return
        }
        disclosureReview = IOSPrivacyConsentConfirmation(
            token: token,
            action: .acceptCurrentDisclosure
        )
    }

    private func privacyBoundary(
        _ text: String,
        image: String
    ) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: image)
                .foregroundStyle(.tint)
        }
        .accessibilityElement(children: .combine)
    }

    private func scheduleAccessibilityAnnouncement(
        _ message: String,
        priority: IOSAccessibilityAnnouncementCandidate.Priority
    ) {
        let incoming = IOSAccessibilityAnnouncementCandidate(
            message: message,
            priority: priority
        )
        let preferred = IOSAccessibilityAnnouncementCandidate.preferred(
            current: accessibilityAnnouncementCandidate,
            incoming: incoming
        )
        guard preferred != accessibilityAnnouncementCandidate else { return }

        accessibilityAnnouncementCandidate = preferred
        accessibilityAnnouncementTask?.cancel()
        accessibilityAnnouncementTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled,
                  accessibilityAnnouncementCandidate == preferred else {
                return
            }
            accessibilityAnnouncementCandidate = nil
            accessibilityAnnouncementTask = nil
            IOSAccessibilityAnnouncement.post(preferred.message)
        }
    }
}

private struct IOSPrivacyConsentConfirmation: Identifiable {
    let id = UUID()
    let token: IOSProviderConsentConfirmationToken
    let action: IOSProviderConsentPrivacyAction
}

private struct IOSProviderConsentPrivacyReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let confirmation: IOSPrivacyConsentConfirmation
    let consentOwner: IOSProviderConsentPresentationOwner

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text(
                            "Review what an explicit Voice action sends, what "
                                + "stays local, and how P4 retains results."
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.tint)
                    }
                }

                IOSProviderConsentDisclosureSections()

                Section {
                    Button {
                        if consentOwner.confirmPrivacyAction(
                            confirmation.token
                        ) == .accepted {
                            dismiss()
                        }
                    } label: {
                        Label(
                            "Accept Current Disclosure",
                            systemImage: "checkmark"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(
                        consentOwner.isBusy
                            || !consentOwner.isPrivacyConfirmationCurrent(
                                confirmation.token
                            )
                    )
                    .accessibilityIdentifier(
                        "ios.privacy.consent.review-accept"
                    )
                } footer: {
                    Text(
                        "You can withdraw later. A request already received "
                            + "by OpenAI cannot be recalled."
                    )
                }
            }
            .navigationTitle("OpenAI Processing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onChange(of: consentOwner.confirmationRevision) { _, _ in
            guard !consentOwner.isPrivacyConfirmationCurrent(
                confirmation.token
            ) else {
                return
            }
            dismiss()
        }
        .accessibilityIdentifier("ios.privacy.consent.review-sheet")
    }
}

struct IOSMicrophonePrivacyPresentation {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color

    static func resolve(_ status: IOSMicrophonePermissionStatus) -> Self {
        switch status {
        case .undetermined:
            Self(
                title: "Not Requested",
                detail:
                    "HoldType asks only after an explicit Start Dictation action.",
                systemImage: "mic.badge.plus",
                color: .secondary
            )
        case .denied:
            Self(
                title: "Access Denied",
                detail:
                    "Allow microphone access in System Settings before recording.",
                systemImage: "mic.slash.fill",
                color: .orange
            )
        case .granted:
            Self(
                title: "Access Granted",
                detail:
                    "HoldType may record only during an explicit Voice attempt.",
                systemImage: "mic.fill",
                color: .green
            )
        case .unavailable:
            Self(
                title: "Status Unavailable",
                detail: "The system microphone status could not be read safely.",
                systemImage: "mic.slash",
                color: .red
            )
        }
    }
}

struct IOSConsentPrivacyPresentation {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
    let action: IOSProviderConsentPrivacyAction?

    static func resolve(
        _ snapshot: IOSProviderConsentPrivacySnapshot
    ) -> Self {
        if snapshot.requiresExplicitAcceptance {
            return Self(
                title: "Acceptance Required",
                detail:
                    "The saved decision remains readable, but provider authority "
                    + "is closed until you accept again.",
                systemImage: "hand.raised",
                color: .orange,
                action: .acceptCurrentDisclosure
            )
        }

        return switch snapshot.status {
        case .notReviewed:
            Self(
                title: "Not Reviewed",
                detail: "Review the OpenAI processing disclosure before Voice.",
                systemImage: "hand.raised",
                color: .secondary,
                action: .acceptCurrentDisclosure
            )
        case .acceptedCurrentDisclosure:
            Self(
                title: "Accepted",
                detail: "OpenAI processing is allowed for explicit Voice actions.",
                systemImage: "checkmark.shield.fill",
                color: .green,
                action: .withdraw
            )
        case .reviewRequired:
            Self(
                title: "Review Required",
                detail: "The processing disclosure changed and needs acceptance.",
                systemImage: "exclamationmark.shield",
                color: .orange,
                action: .acceptCurrentDisclosure
            )
        case .withdrawn:
            Self(
                title: "Withdrawn",
                detail: "OpenAI provider authority is closed.",
                systemImage: "hand.raised.slash",
                color: .orange,
                action: .acceptCurrentDisclosure
            )
        case .localDataUnavailable:
            Self(
                title: "Consent Data Unavailable",
                detail:
                    "HoldType cannot safely read the local consent record.",
                systemImage: "exclamationmark.triangle",
                color: .red,
                action: nil
            )
        case .mutationNotSaved:
            Self(
                title: "Decision Not Saved",
                detail:
                    "The previous durable decision remains active until retry.",
                systemImage: "externaldrive.badge.exclamationmark",
                color: .orange,
                action: nil
            )
        }
    }
}

private extension IOSProviderConsentPrivacyAction {
    var buttonTitle: String {
        switch self {
        case .acceptCurrentDisclosure:
            "Review and Accept"
        case .withdraw:
            "Withdraw Consent"
        case .resetUnreadableData:
            "Reset Unreadable Consent Data"
        }
    }

    var buttonRole: ButtonRole? {
        switch self {
        case .acceptCurrentDisclosure:
            nil
        case .withdraw, .resetUnreadableData:
            .destructive
        }
    }

    var confirmationTitle: String {
        switch self {
        case .acceptCurrentDisclosure:
            "Accept OpenAI Processing?"
        case .withdraw:
            "Withdraw OpenAI Processing Consent?"
        case .resetUnreadableData:
            "Reset Unreadable Consent Data?"
        }
    }

    var confirmationButtonTitle: String {
        switch self {
        case .acceptCurrentDisclosure:
            "Accept"
        case .withdraw:
            "Withdraw Consent"
        case .resetUnreadableData:
            "Reset Consent Data"
        }
    }

    var confirmationRole: ButtonRole? {
        buttonRole
    }

    var confirmationMessage: String {
        switch self {
        case .acceptCurrentDisclosure:
            "This allows OpenAI processing only for explicit Voice actions."
        case .withdraw:
            "Provider authority closes immediately. Any valid partial recording "
                + "remains available for Recover or Discard. Other app data is "
                + "not deleted. A request already received by OpenAI cannot "
                + "be recalled."
        case .resetUnreadableData:
            "This removes only the exact unreadable consent record. It does "
                + "not delete your API key, settings, History, or results."
        }
    }

    var accessibilityName: String {
        switch self {
        case .acceptCurrentDisclosure:
            "accept"
        case .withdraw:
            "withdraw"
        case .resetUnreadableData:
            "reset-unreadable"
        }
    }
}

private extension IOSProviderConsentPresentationOperation {
    var progressTitle: String {
        switch self {
        case .idle:
            "Ready"
        case .acceptingVoice, .acceptingPrivacy:
            "Saving acceptance…"
        case .decliningVoice, .withdrawingPrivacy:
            "Saving withdrawal…"
        case .resettingUnreadableData:
            "Resetting consent data…"
        }
    }
}

private extension IOSProviderConsentPresentationNotice {
    var title: String {
        switch self {
        case .accepted:
            "Consent accepted"
        case .withdrawn:
            "Consent withdrawn"
        case .unreadableDataReset:
            "Unreadable consent data reset"
        }
    }
}

private extension IOSProviderConsentPresentationFailure {
    var detail: String {
        switch self {
        case .statusChanged:
            "Consent changed in another operation. Review the current status."
        case .localDataUnavailable:
            "The local consent record could not be verified safely."
        case .decisionNotSaved:
            "The decision was not saved. The prior durable state remains."
        case .operationFailed:
            "The consent action failed without changing unrelated app data."
        }
    }
}
