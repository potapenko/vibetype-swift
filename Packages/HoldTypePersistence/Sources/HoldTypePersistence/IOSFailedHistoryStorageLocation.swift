import Foundation

/// Stable app-private location for canonical failed iOS History state.
enum IOSFailedHistoryStorageLocation {
    static let directoryName = "HoldType"
    static let fileName = "ios-failed-history.json"

    static func fileURL(in applicationSupportDirectoryURL: URL) -> URL {
        applicationSupportDirectoryURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}

extension IOSStrictProtectedRecordConfiguration {
    static let failedHistory = Self(
        rootDirectoryName: IOSFailedHistoryStorageLocation.directoryName,
        fileName: IOSFailedHistoryStorageLocation.fileName,
        maximumByteCount: IOSFailedHistoryJournal.maximumByteCount,
        marker: Marker(
            name: "com.holdtype.ios.failed-history",
            value: Array("v1".utf8)
        )
    )
}
