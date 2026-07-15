import Foundation
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSKeyboardHandoffLaunchRouterTests {
    @Test func validFreshMatchingIntentSelectsVoiceWithoutStartingCapture()
        throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let requestID = UUID()
        let candidate = HoldTypeIOS.KeyboardHandoffIntentRecord(
            requestID: requestID,
            sourceDocumentID: UUID(),
            action: .improve,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(10)
        )
        let intent = try #require(candidate)
        var consumedRequestIDs: [UUID] = []
        let router = IOSKeyboardHandoffLaunchRouter(
            now: { now },
            consume: { candidate, _ in
                consumedRequestIDs.append(candidate)
                return candidate == requestID ? intent : nil
            }
        )
        let url = try #require(
            KeyboardHandoffLaunchRoute(requestID: requestID).url
        )

        let decision = router.resolve(url)

        #expect(decision == .keyboardHandoff(intent))
        #expect(consumedRequestIDs == [requestID])
    }

    @Test func settingsRoutingRemainsIndependentOfHandoffStorage() throws {
        var consumeCount = 0
        let router = IOSKeyboardHandoffLaunchRouter(
            now: { Date() },
            consume: { _, _ in
                consumeCount += 1
                return nil
            }
        )
        let url = try #require(IOSSettingsAttention.fullAccess.launchURL)

        #expect(router.resolve(url) == .settings(.fullAccess))
        #expect(consumeCount == 0)
    }

    @Test func malformedAndUnmatchedLaunchesAreInert() throws {
        let requestID = UUID()
        var consumedRequestIDs: [UUID] = []
        let router = IOSKeyboardHandoffLaunchRouter(
            now: { Date(timeIntervalSince1970: 1_750_000_000) },
            consume: { candidate, _ in
                consumedRequestIDs.append(candidate)
                return nil
            }
        )
        let malformedURLs = [
            "holdtype://keyboard-handoff/not-a-uuid",
            "holdtype://keyboard-handoff/\(requestID.uuidString)?payload=x",
            "holdtype://other/\(requestID.uuidString)",
            "https://example.com",
        ]
        for rawURL in malformedURLs {
            #expect(
                router.resolve(
                    try #require(URL(string: rawURL))
                ) == .ignore
            )
        }

        let unmatchedURL = try #require(
            KeyboardHandoffLaunchRoute(requestID: requestID).url
        )
        #expect(router.resolve(unmatchedURL) == .ignore)
        #expect(consumedRequestIDs == [requestID])
    }

    @Test func repeatedLaunchIsAcceptedAtMostOnce() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let requestID = UUID()
        let candidate = HoldTypeIOS.KeyboardHandoffIntentRecord(
            requestID: requestID,
            sourceDocumentID: nil,
            action: .standard,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(10)
        )
        let intent = try #require(candidate)
        var pending: HoldTypeIOS.KeyboardHandoffIntentRecord? = intent
        let router = IOSKeyboardHandoffLaunchRouter(
            now: { now },
            consume: { candidate, _ in
                guard pending?.requestID == candidate else { return nil }
                defer { pending = nil }
                return pending
            }
        )
        let url = try #require(
            KeyboardHandoffLaunchRoute(requestID: requestID).url
        )

        #expect(router.resolve(url) == .keyboardHandoff(intent))
        #expect(router.resolve(url) == .ignore)
    }
}
