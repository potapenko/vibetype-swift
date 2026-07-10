import Foundation

/// Stable app-private location for the canonical iOS History policy.
public enum IOSHistoryPolicyStorageLocation {
    public static let directoryName = "HoldType"
    public static let fileName = "ios-history-policy.json"

    public static func fileURL(in applicationSupportDirectoryURL: URL) -> URL {
        applicationSupportDirectoryURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}

extension IOSStrictProtectedRecordConfiguration {
    static let historyPolicy = Self(
        rootDirectoryName: IOSHistoryPolicyStorageLocation.directoryName,
        fileName: IOSHistoryPolicyStorageLocation.fileName,
        maximumByteCount: IOSHistoryPolicyJournal.maximumByteCount,
        marker: Marker(
            name: "com.holdtype.ios.history-policy",
            value: Array("v1".utf8)
        )
    )
}
