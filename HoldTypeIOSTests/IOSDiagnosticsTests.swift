import Foundation
import Testing
@testable import HoldTypeIOS

struct IOSDiagnosticsTests {
    @Test func runtimeLogsAreTypedSeparatedAndContentFree() throws {
        let root = temporaryDiagnosticsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = diagnosticDate("2026-07-15T09:30:00.000Z")
        let app = HoldTypeIOS.IOSRuntimeDiagnosticsStore(
            process: .app,
            rootDirectoryURL: root,
            now: { now }
        )
        let keyboard = HoldTypeIOS.IOSRuntimeDiagnosticsStore(
            process: .keyboard,
            rootDirectoryURL: root,
            now: { now }
        )

        app.record(
            .voiceStartRequested(origin: .foreground, action: .translate)
        )
        let attemptID = UUID(
            uuidString: "A0000000-0000-0000-0000-000000000000"
        )!
        app.record(
            .voiceStopResolved(
                reason: .interrupted,
                durability: .recoverableCapture,
                providerAuthority: .absent,
                attempt: HoldTypeIOS.IOSDiagnosticCorrelationTag(attemptID)
            )
        )
        keyboard.record(
            .keyboardCommand(
                .start,
                action: .improve,
                outcome: .succeeded
            )
        )
        let requestID = UUID(
            uuidString: "A0000000-0000-0000-0000-000000000001"
        )!
        let claimID = UUID(
            uuidString: "A0000000-0000-0000-0000-000000000002"
        )!
        let sourceDocumentID = UUID(
            uuidString: "A0000000-0000-0000-0000-000000000003"
        )!
        let currentDocumentID = UUID(
            uuidString: "A0000000-0000-0000-0000-000000000004"
        )!
        let controllerLifetimeID = UUID(
            uuidString: "A0000000-0000-0000-0000-000000000005"
        )!
        keyboard.record(.keyboardInsertInvoked(.latest))
        keyboard.record(
            .keyboardDelivery(
                .insertReturned,
                request: HoldTypeIOS.IOSDiagnosticCorrelationTag(requestID),
                claim: HoldTypeIOS.IOSDiagnosticCorrelationTag(claimID),
                sourceDocument: HoldTypeIOS.IOSDiagnosticCorrelationTag(
                    sourceDocumentID
                ),
                currentDocument: HoldTypeIOS.IOSDiagnosticCorrelationTag(
                    currentDocumentID
                ),
                controllerLifetime: HoldTypeIOS.IOSDiagnosticCorrelationTag(
                    controllerLifetimeID
                )
            )
        )

        let appLines = try app.recentLines(limit: 10)
        let appLine = try #require(appLines.first)
        let voiceStopLine = try #require(
            appLines.first(where: {
                $0.contains("event=voice_stop_resolved")
            })
        )
        let keyboardLines = try keyboard.recentLines(limit: 10)
        let keyboardCommandLine = try #require(keyboardLines.first)
        let keyboardInsertionLine = try #require(
            keyboardLines.first(where: {
                $0.contains("event=keyboard_insert_invoked")
            })
        )
        let keyboardDeliveryLine = try #require(
            keyboardLines.first(where: {
                $0.contains("event=keyboard_delivery")
            })
        )
        #expect(appLine.contains("process=app"))
        #expect(appLine.contains("event=voice_start_requested"))
        #expect(appLine.contains("action=translate"))
        #expect(voiceStopLine.contains("reason=interrupted"))
        #expect(voiceStopLine.contains("durability=recoverable_capture"))
        #expect(voiceStopLine.contains("provider_authority=absent"))
        #expect(voiceStopLine.contains("attempt_tag="))
        #expect(!voiceStopLine.contains(attemptID.uuidString))
        #expect(keyboardCommandLine.contains("process=keyboard"))
        #expect(keyboardCommandLine.contains("command=start"))
        #expect(keyboardCommandLine.contains("action=improve"))
        #expect(keyboardInsertionLine.contains("kind=latest"))
        #expect(!keyboardInsertionLine.contains("keyboard_result_inserted"))
        #expect(keyboardDeliveryLine.contains("event=keyboard_delivery"))
        #expect(keyboardDeliveryLine.contains("stage=insert_returned"))
        #expect(keyboardDeliveryLine.contains("request_tag="))
        #expect(keyboardDeliveryLine.contains("claim_tag="))
        #expect(keyboardDeliveryLine.contains("source_document_tag="))
        #expect(keyboardDeliveryLine.contains("current_document_tag="))
        #expect(keyboardDeliveryLine.contains("controller_lifetime_tag="))
        #expect(!keyboardDeliveryLine.contains("proxy_has_text="))
        #expect(!keyboardDeliveryLine.contains(requestID.uuidString))
        #expect(!keyboardDeliveryLine.contains(claimID.uuidString))
        #expect(!keyboardDeliveryLine.contains(sourceDocumentID.uuidString))
        #expect(!keyboardDeliveryLine.contains(currentDocumentID.uuidString))
        #expect(!keyboardDeliveryLine.contains(controllerLifetimeID.uuidString))
        #expect(!appLine.contains("transcript"))
        #expect(!keyboardDeliveryLine.contains("typed_text"))
    }

    @Test func runtimeRetentionPrunesExpiredDays() throws {
        let root = temporaryDiagnosticsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = DiagnosticClock(
            diagnosticDate("2026-07-01T10:00:00.000Z")
        )
        let store = HoldTypeIOS.IOSRuntimeDiagnosticsStore(
            process: .app,
            rootDirectoryURL: root,
            now: { clock.value }
        )

        store.record(.appLaunched)
        clock.value = diagnosticDate("2026-07-15T10:00:00.000Z")
        store.record(.scenePhase(.active))

        let lines = try store.recentLines(limit: 10)
        #expect(lines.count == 1)
        #expect(lines[0].contains("event=scene_phase_changed"))
    }

    @Test func exportUsesOneReadableFileAndFortyEightHourWindow() throws {
        let root = temporaryDiagnosticsRoot()
        let exportRoot = root.appendingPathComponent("Exports")
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = DiagnosticClock(
            diagnosticDate("2026-07-12T08:00:00.000Z")
        )
        let app = HoldTypeIOS.IOSRuntimeDiagnosticsStore(
            process: .app,
            rootDirectoryURL: root,
            now: { clock.value }
        )
        let keyboard = HoldTypeIOS.IOSRuntimeDiagnosticsStore(
            process: .keyboard,
            rootDirectoryURL: root,
            now: { clock.value }
        )
        let metrics = IOSMetricDiagnosticStore(
            rootDirectoryURL: root,
            now: { clock.value }
        )
        app.record(.appLaunched)
        clock.value = diagnosticDate("2026-07-15T08:00:00.000Z")
        app.record(.scenePhase(.active))
        keyboard.record(.keyboardState(.sessionReady))
        try metrics.store(
            IOSMetricDiagnosticRecord(
                receivedAt: clock.value,
                intervalStart: diagnosticDate(
                    "2026-07-14T00:00:00.000Z"
                ),
                intervalEnd: diagnosticDate(
                    "2026-07-15T00:00:00.000Z"
                ),
                crashCount: 1,
                hangCount: 0,
                cpuExceptionCount: 0,
                diskWriteCount: 0,
                payloadJSON: "{\"diagnosticMetaData\":{}}"
            )
        )
        let service = IOSDiagnosticsService(
            appLog: app,
            keyboardLog: keyboard,
            metricStore: metrics,
            now: { clock.value },
            exportDirectoryURL: exportRoot
        )
        let snapshot = service.snapshot(
            metadata: IOSDiagnosticsMetadata(
                appVersion: "1.2.3",
                buildNumber: "45",
                operatingSystem: "iOS 26.0",
                deviceFamily: "iPhone"
            )
        )

        let fileURL = try service.makeDiagnosticFile(from: snapshot)
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let exports = try FileManager.default.contentsOfDirectory(
            at: exportRoot,
            includingPropertiesForKeys: nil
        )

        #expect(exports == [fileURL])
        #expect(text.contains("HoldType Diagnostics"))
        #expect(text.contains("App version: 1.2.3"))
        #expect(text.contains("event=scene_phase_changed"))
        #expect(text.contains("process=keyboard"))
        #expect(!text.contains("2026-07-12T08:00:00.000Z"))
        #expect(text.contains("crashes=1"))
        #expect(text.contains("diagnosticMetaData"))
        #expect(text.contains("excludes dictated text"))
    }

    @Test func metricStoreIgnoresEmptyAndPrunesExpiredDelivery() throws {
        let root = temporaryDiagnosticsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = DiagnosticClock(
            diagnosticDate("2026-07-01T10:00:00.000Z")
        )
        let store = IOSMetricDiagnosticStore(
            rootDirectoryURL: root,
            now: { clock.value }
        )
        try store.store(
            IOSMetricDiagnosticRecord(
                receivedAt: clock.value,
                intervalStart: clock.value,
                intervalEnd: clock.value,
                crashCount: 1,
                hangCount: 0,
                cpuExceptionCount: 0,
                diskWriteCount: 0,
                payloadJSON: "{}"
            )
        )
        #expect(try store.records().count == 1)

        clock.value = diagnosticDate("2026-07-15T10:00:00.000Z")
        #expect(try store.records().isEmpty)

        try store.store(
            IOSMetricDiagnosticRecord(
                receivedAt: clock.value,
                intervalStart: clock.value,
                intervalEnd: clock.value,
                crashCount: 0,
                hangCount: 0,
                cpuExceptionCount: 0,
                diskWriteCount: 0,
                payloadJSON: "{}"
            )
        )
        #expect(try store.records().isEmpty)
    }
}

private final class DiagnosticClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date

    init(_ value: Date) {
        storedValue = value
    }

    var value: Date {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private func temporaryDiagnosticsRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
        "HoldType-IOSDiagnosticsTests-\(UUID().uuidString)",
        isDirectory: true
    )
}

private func diagnosticDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [
        .withInternetDateTime,
        .withFractionalSeconds,
    ]
    return formatter.date(from: value)!
}
