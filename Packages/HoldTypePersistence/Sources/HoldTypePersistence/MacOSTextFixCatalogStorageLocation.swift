import Foundation

/// Stable local location for the macOS app's versioned Fixes catalog.
public enum MacOSTextFixCatalogStorageLocation {
    public static let directoryName = "HoldType"
    public static let fileName = "macos-text-fixes.json"

    public static func fileURL(in applicationSupportDirectoryURL: URL) -> URL {
        applicationSupportDirectoryURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
