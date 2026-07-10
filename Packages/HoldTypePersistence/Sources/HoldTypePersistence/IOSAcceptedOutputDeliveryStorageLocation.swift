import Foundation

/// Stable app-private location for the current accepted iOS output delivery.
public enum IOSAcceptedOutputDeliveryStorageLocation {
    public static let directoryName = "HoldType"
    public static let fileName = "ios-accepted-output-delivery.json"

    public static func fileURL(in applicationSupportDirectoryURL: URL) -> URL {
        applicationSupportDirectoryURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}

extension IOSStrictProtectedRecordConfiguration {
    static let acceptedOutputDelivery = Self(
        rootDirectoryName: IOSAcceptedOutputDeliveryStorageLocation.directoryName,
        fileName: IOSAcceptedOutputDeliveryStorageLocation.fileName,
        maximumByteCount: IOSAcceptedOutputDeliveryJournal.maximumByteCount,
        marker: Marker(
            name: "com.holdtype.ios.accepted-output-delivery",
            value: Array("v1".utf8)
        )
    )
}
