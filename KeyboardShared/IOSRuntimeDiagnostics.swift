import Foundation
import OSLog

nonisolated enum IOSDiagnosticProcess: String, CaseIterable, Sendable {
    case app
    case keyboard
}

nonisolated enum IOSDiagnosticSeverity: String, Sendable {
    case info
    case error
}

nonisolated enum IOSDiagnosticScenePhase: String, Sendable {
    case active
    case inactive
    case background
}

nonisolated enum IOSDiagnosticVoiceOrigin: String, Sendable {
    case foreground
    case keyboard
}

nonisolated enum IOSDiagnosticVoiceAction: String, Sendable {
    case standard
    case translate
    case improve
    case translateAndImprove = "translate_and_improve"
}

nonisolated enum IOSDiagnosticVoiceStopReason: String, Sendable {
    case done
    case cancelled
    case interrupted
    case maximumDuration = "maximum_duration"
}

nonisolated enum IOSDiagnosticProviderMode: String, Sendable {
    case initial
    case retry
}

nonisolated enum IOSDiagnosticOutcome: String, Sendable {
    case succeeded
    case failed
    case unavailable
    case cancelled
    case timedOut = "timed_out"
    case stale
}

nonisolated enum IOSDiagnosticAudioEvent: String, Sendable {
    case activationStarted = "activation_started"
    case activated
    case activationFailed = "activation_failed"
    case inputValidated = "input_validated"
    case inputInvalid = "input_invalid"
    case interrupted
    case deactivated
}

nonisolated enum IOSDiagnosticKeyboardState: String, Sendable {
    case opened
    case closed
    case noSharedAccess = "no_shared_access"
    case sessionReady = "session_ready"
    case sessionUnavailable = "session_unavailable"
    case listening
    case processing
    case resultReady = "result_ready"
    case failed
    case expired
}

nonisolated enum IOSDiagnosticKeyboardCommand: String, Sendable {
    case start
    case finish
    case cancel
    case claimDelivery = "claim_delivery"
    case acknowledgeDelivery = "acknowledge_delivery"
}

nonisolated enum IOSDiagnosticInsertionKind: String, Sendable {
    case latest
    case dictation
}

nonisolated enum IOSDiagnosticMetricKind: String, Sendable {
    case crash
    case hang
    case cpuException = "cpu_exception"
    case diskWrite = "disk_write"
}

nonisolated enum IOSDiagnosticDurationBucket: String, Sendable {
    case underOneSecond = "under_1s"
    case oneToTenSeconds = "1s_10s"
    case tenToSixtySeconds = "10s_60s"
    case oneToFiveMinutes = "1m_5m"
    case overFiveMinutes = "over_5m"

    init(duration: TimeInterval) {
        switch duration {
        case ..<1:
            self = .underOneSecond
        case ..<10:
            self = .oneToTenSeconds
        case ..<60:
            self = .tenToSixtySeconds
        case ..<300:
            self = .oneToFiveMinutes
        default:
            self = .overFiveMinutes
        }
    }
}

/// Closed, content-free event vocabulary shared by the iOS app and keyboard.
/// Callers cannot attach arbitrary strings, paths, text, prompts, or payloads.
nonisolated enum IOSRuntimeDiagnosticEvent: Sendable {
    case appLaunched
    case scenePhase(IOSDiagnosticScenePhase)
    case voiceStartRequested(
        origin: IOSDiagnosticVoiceOrigin,
        action: IOSDiagnosticVoiceAction
    )
    case voiceRecordingStarted(origin: IOSDiagnosticVoiceOrigin)
    case voiceStopRequested(IOSDiagnosticVoiceStopReason)
    case voiceRecordingStopped(IOSDiagnosticDurationBucket)
    case voiceCompleted(IOSDiagnosticOutcome)
    case audio(IOSDiagnosticAudioEvent)
    case providerStarted(IOSDiagnosticProviderMode)
    case providerCompleted(IOSDiagnosticOutcome)
    case keyboardState(IOSDiagnosticKeyboardState)
    case keyboardCommand(
        IOSDiagnosticKeyboardCommand,
        action: IOSDiagnosticVoiceAction,
        outcome: IOSDiagnosticOutcome
    )
    case keyboardInserted(IOSDiagnosticInsertionKind)
    case diagnosticsExported(IOSDiagnosticOutcome)
    case metricDiagnosticsReceived(IOSDiagnosticMetricKind, count: Int)

    fileprivate var category: String {
        switch self {
        case .appLaunched, .scenePhase:
            "lifecycle"
        case .voiceStartRequested, .voiceRecordingStarted,
             .voiceStopRequested, .voiceRecordingStopped, .voiceCompleted:
            "voice"
        case .audio:
            "audio"
        case .providerStarted, .providerCompleted:
            "provider"
        case .keyboardState, .keyboardCommand, .keyboardInserted:
            "keyboard"
        case .diagnosticsExported, .metricDiagnosticsReceived:
            "diagnostics"
        }
    }

    fileprivate var name: String {
        switch self {
        case .appLaunched:
            "app_launched"
        case .scenePhase:
            "scene_phase_changed"
        case .voiceStartRequested:
            "voice_start_requested"
        case .voiceRecordingStarted:
            "voice_recording_started"
        case .voiceStopRequested:
            "voice_stop_requested"
        case .voiceRecordingStopped:
            "voice_recording_stopped"
        case .voiceCompleted:
            "voice_completed"
        case .audio:
            "audio_session_event"
        case .providerStarted:
            "provider_started"
        case .providerCompleted:
            "provider_completed"
        case .keyboardState:
            "keyboard_state_changed"
        case .keyboardCommand:
            "keyboard_command"
        case .keyboardInserted:
            "keyboard_result_inserted"
        case .diagnosticsExported:
            "diagnostic_export"
        case .metricDiagnosticsReceived:
            "metric_diagnostics_received"
        }
    }

    fileprivate var severity: IOSDiagnosticSeverity {
        switch self {
        case .voiceCompleted(.failed), .voiceCompleted(.unavailable),
             .audio(.activationFailed), .audio(.inputInvalid),
             .providerCompleted(.failed), .providerCompleted(.unavailable),
             .keyboardState(.failed),
             .keyboardCommand(_, _, .failed),
             .keyboardCommand(_, _, .unavailable),
             .diagnosticsExported(.failed):
            .error
        default:
            .info
        }
    }

    fileprivate var fields: [String] {
        switch self {
        case .appLaunched:
            []
        case .scenePhase(let phase):
            ["phase=\(phase.rawValue)"]
        case .voiceStartRequested(let origin, let action):
            ["origin=\(origin.rawValue)", "action=\(action.rawValue)"]
        case .voiceRecordingStarted(let origin):
            ["origin=\(origin.rawValue)"]
        case .voiceStopRequested(let reason):
            ["reason=\(reason.rawValue)"]
        case .voiceRecordingStopped(let duration):
            ["duration_bucket=\(duration.rawValue)"]
        case .voiceCompleted(let outcome),
             .providerCompleted(let outcome),
             .diagnosticsExported(let outcome):
            ["outcome=\(outcome.rawValue)"]
        case .audio(let event):
            ["state=\(event.rawValue)"]
        case .providerStarted(let mode):
            ["mode=\(mode.rawValue)"]
        case .keyboardState(let state):
            ["state=\(state.rawValue)"]
        case .keyboardCommand(let command, let action, let outcome):
            [
                "command=\(command.rawValue)",
                "action=\(action.rawValue)",
                "outcome=\(outcome.rawValue)",
            ]
        case .keyboardInserted(let kind):
            ["kind=\(kind.rawValue)"]
        case .metricDiagnosticsReceived(let kind, let count):
            ["kind=\(kind.rawValue)", "count=\(max(0, count))"]
        }
    }
}

nonisolated enum IOSDiagnosticsStorage {
    static let appGroupIdentifier = "group.app.holdtype.HoldType.shared"

    static func rootDirectoryURL(
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )?
        .appendingPathComponent("Diagnostics", isDirectory: true)
    }
}

nonisolated final class IOSRuntimeDiagnosticsStore: @unchecked Sendable {
    static let app = IOSRuntimeDiagnosticsStore(process: .app)
    static let keyboard = IOSRuntimeDiagnosticsStore(process: .keyboard)

    let process: IOSDiagnosticProcess
    let directoryURL: URL?

    private let fileManager: FileManager
    private let now: @Sendable () -> Date
    private let maximumAge: TimeInterval
    private let maximumTotalByteCount: Int64
    private let lock = NSLock()
    private let subsystem: String

    init(
        process: IOSDiagnosticProcess,
        rootDirectoryURL: URL? = IOSDiagnosticsStorage.rootDirectoryURL(),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        maximumAge: TimeInterval = 7 * 24 * 60 * 60,
        maximumTotalByteCount: Int64 = 2_500_000,
        subsystem: String = Bundle.main.bundleIdentifier
            ?? "app.holdtype.HoldType.ios"
    ) {
        self.process = process
        self.fileManager = fileManager
        self.now = now
        self.maximumAge = maximumAge
        self.maximumTotalByteCount = maximumTotalByteCount
        self.subsystem = subsystem
        directoryURL = rootDirectoryURL?
            .appendingPathComponent("RuntimeLogs", isDirectory: true)
            .appendingPathComponent(process.rawValue, isDirectory: true)
    }

    func record(_ event: IOSRuntimeDiagnosticEvent) {
        let date = now()
        let line = Self.line(for: event, process: process, at: date)
        let logger = Logger(subsystem: subsystem, category: event.category)
        switch event.severity {
        case .info:
            logger.info("\(line, privacy: .public)")
        case .error:
            logger.error("\(line, privacy: .public)")
        }

        guard directoryURL != nil else { return }
        lock.withLock {
            do {
                try append(line, at: date)
                try pruneLocked()
            } catch {
                // Diagnostics must never interrupt app or keyboard behavior.
            }
        }
    }

    func recentLines(limit: Int, since startDate: Date? = nil) throws -> [String] {
        guard limit > 0 else { return [] }
        return try lock.withLock {
            try pruneLocked()
            let lines = try allLinesLocked()
            let filtered = lines.filter { line in
                guard let startDate else { return true }
                guard let date = Self.date(from: line) else { return false }
                return date >= startDate
            }
            return Array(filtered.suffix(limit))
        }
    }

    func prune() throws {
        try lock.withLock {
            try pruneLocked()
        }
    }

    private func append(_ line: String, at date: Date) throws {
        guard let directoryURL else { return }
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try excludeFromBackup(directoryURL)
        let fileURL = directoryURL.appendingPathComponent(
            "runtime-\(Self.fileDate(date))-\(process.rawValue).log"
        )
        let data = Data((line + "\n").utf8)
        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(
                to: fileURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            try excludeFromBackup(fileURL)
        }
    }

    private func pruneLocked() throws {
        guard let directoryURL,
              fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }
        let cutoff = now().addingTimeInterval(-maximumAge)
        for fileURL in try logFileURLsLocked() {
            let values = try fileURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            )
            let fileDate = Self.logFileDate(fileURL)
                ?? values.contentModificationDate
                ?? .distantPast
            if fileDate.addingTimeInterval(24 * 60 * 60) < cutoff {
                try fileManager.removeItem(at: fileURL)
            }
        }

        let files = try logFileURLsLocked().map { fileURL in
            let values = try fileURL.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            )
            return (
                url: fileURL,
                size: Int64(values.fileSize ?? 0),
                date: values.contentModificationDate ?? .distantPast
            )
        }
        .sorted { $0.date > $1.date }

        var retainedBytes: Int64 = 0
        for file in files {
            retainedBytes += file.size
            if retainedBytes > maximumTotalByteCount {
                try fileManager.removeItem(at: file.url)
            }
        }
    }

    private func allLinesLocked() throws -> [String] {
        var lines: [String] = []
        for fileURL in try logFileURLsLocked() {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            lines.append(contentsOf:
                contents.split(whereSeparator: \.isNewline).map(String.init)
            )
        }
        return lines.sorted()
    }

    private func logFileURLsLocked() throws -> [URL] {
        guard let directoryURL,
              fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }
        return try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
            ],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent.hasPrefix("runtime-") }
        .filter { $0.pathExtension == "log" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private static func line(
        for event: IOSRuntimeDiagnosticEvent,
        process: IOSDiagnosticProcess,
        at date: Date
    ) -> String {
        ([
            timestamp(date),
            "process=\(process.rawValue)",
            "category=\(event.category)",
            "event=\(event.name)",
            "severity=\(event.severity.rawValue)",
        ] + event.fields).joined(separator: " ")
    }

    private static func date(from line: String) -> Date? {
        guard let timestamp = line.split(separator: " ").first else {
            return nil
        }
        return isoFormatter().date(from: String(timestamp))
    }

    private static func timestamp(_ date: Date) -> String {
        isoFormatter().string(from: date)
    }

    private static func isoFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        return formatter
    }

    private static func fileDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static func logFileDate(_ fileURL: URL) -> Date? {
        let name = fileURL.deletingPathExtension().lastPathComponent
        guard name.hasPrefix("runtime-"), name.count >= 16 else {
            return nil
        }
        let start = name.index(name.startIndex, offsetBy: 8)
        let end = name.index(start, offsetBy: 8)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: String(name[start..<end]))
    }
}
