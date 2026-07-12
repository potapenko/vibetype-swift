import Foundation

/// Stable app-private location for the containing app's provider-consent authority.
public enum IOSProviderConsentStorageLocation {
    public static let directoryName = "HoldType"
    public static let fileName = "ios-openai-provider-consent.json"

    public static func fileURL(in applicationSupportDirectoryURL: URL) -> URL {
        applicationSupportDirectoryURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}

enum IOSProviderConsentStoragePolicy {
    static let maximumByteCount = 4_096
    static let excludesFromBackup = false
}

extension IOSStrictProtectedRecordConfiguration {
    static let providerConsent = Self(
        rootDirectoryName: IOSProviderConsentStorageLocation.directoryName,
        fileName: IOSProviderConsentStorageLocation.fileName,
        maximumByteCount: IOSProviderConsentStoragePolicy.maximumByteCount,
        marker: Marker(
            name: "com.holdtype.ios.provider-consent",
            value: Array("v1".utf8)
        )
    )
}
