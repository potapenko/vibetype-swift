import Foundation

/// Stable app-private location for the containing app's versioned Library file.
public enum IOSLibraryStorageLocation {
    public static let directoryName = "HoldType"
    public static let fileName = "ios-library.json"

    public static func fileURL(in applicationSupportDirectoryURL: URL) -> URL {
        applicationSupportDirectoryURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
