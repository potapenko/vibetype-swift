import CoreFoundation
import Foundation

enum IOSProviderConsentWireCodecError: Error, Equatable, Sendable {
    case sourceTooLarge
    case malformedData
    case invalidRecord
    case unsupportedSchemaVersion
}

extension IOSProviderConsentWireCodecError:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSProviderConsentWireCodecError(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSProviderConsentWireCodec {
    private static let supportedSchemaVersion: Int64 = 1
    private static let fields: Set<String> = [
        "schemaVersion",
        "epochID",
        "revision",
        "disclosureVersion",
        "state",
        "decisionAt",
    ]
    private static let dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"

    static func encode(_ record: IOSProviderConsentRecord) throws -> Data {
        guard record.revision > 0,
              record.disclosureVersion > 0 else {
            throw IOSProviderConsentWireCodecError.invalidRecord
        }

        let timestamp = try timestampString(from: record.decisionAt)
        let wire = IOSProviderConsentWireV1(
            epochID: record.epochID.uuidString.lowercased(),
            revision: record.revision,
            disclosureVersion: record.disclosureVersion,
            state: record.state.rawValue,
            decisionAt: timestamp
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            let data = try encoder.encode(wire)
            guard data.count <= IOSProviderConsentStoragePolicy.maximumByteCount else {
                throw IOSProviderConsentWireCodecError.sourceTooLarge
            }
            return data
        } catch let error as IOSProviderConsentWireCodecError {
            throw error
        } catch {
            throw IOSProviderConsentWireCodecError.invalidRecord
        }
    }

    static func decode(_ data: Data) throws -> IOSProviderConsentRecord {
        do {
            try BoundedJSONMemberValidator.validate(
                data,
                limits: BoundedJSONMemberValidationLimits(
                    maximumInputByteCount:
                        IOSProviderConsentStoragePolicy.maximumByteCount,
                    maximumNestingDepth: 1,
                    maximumMembersPerObject: 6,
                    maximumTotalObjectMembers: 6,
                    maximumElementsPerArray: 0,
                    maximumTotalValues: 7,
                    maximumDecodedKeyByteCount: 64,
                    maximumDecodedValueStringByteCount: 128,
                    maximumNumberTokenByteCount: 20
                )
            )
        } catch BoundedJSONMemberValidationError.inputTooLarge {
            throw IOSProviderConsentWireCodecError.sourceTooLarge
        } catch {
            throw IOSProviderConsentWireCodecError.malformedData
        }

        let rootValue: Any
        do {
            rootValue = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw IOSProviderConsentWireCodecError.malformedData
        }
        guard let object = rootValue as? [String: Any] else {
            throw IOSProviderConsentWireCodecError.invalidRecord
        }

        let reader = IOSProviderConsentWireObjectReader(object: object)
        let schemaVersion = try reader.integer64("schemaVersion")
        guard schemaVersion == supportedSchemaVersion else {
            throw IOSProviderConsentWireCodecError.unsupportedSchemaVersion
        }
        guard Set(object.keys) == fields else {
            throw IOSProviderConsentWireCodecError.invalidRecord
        }

        let epochString = try reader.string("epochID")
        guard let epochID = UUID(uuidString: epochString),
              epochString == epochID.uuidString.lowercased() else {
            throw IOSProviderConsentWireCodecError.invalidRecord
        }
        let revision = try reader.integer64("revision")
        let disclosureVersion = try reader.integer64("disclosureVersion")
        guard revision > 0, disclosureVersion > 0 else {
            throw IOSProviderConsentWireCodecError.invalidRecord
        }
        guard let state = IOSProviderConsentDecisionState(
            rawValue: try reader.string("state")
        ) else {
            throw IOSProviderConsentWireCodecError.invalidRecord
        }
        let decisionAt = try date(from: reader.string("decisionAt"))

        return IOSProviderConsentRecord(
            epochID: epochID,
            revision: revision,
            disclosureVersion: disclosureVersion,
            state: state,
            decisionAt: decisionAt
        )
    }

    static func canonicalDate(_ date: Date) throws -> Date {
        try self.date(from: timestampString(from: date))
    }

    private static func timestampString(from date: Date) throws -> String {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw IOSProviderConsentWireCodecError.invalidRecord
        }
        let value = makeDateFormatter().string(from: date)
        guard value.utf8.count == 24,
              (try? self.date(from: value)) != nil else {
            throw IOSProviderConsentWireCodecError.invalidRecord
        }
        return value
    }

    private static func date(from value: String) throws -> Date {
        guard value.utf8.count == 24 else {
            throw IOSProviderConsentWireCodecError.invalidRecord
        }
        let formatter = makeDateFormatter()
        guard let date = formatter.date(from: value),
              formatter.string(from: date) == value else {
            throw IOSProviderConsentWireCodecError.invalidRecord
        }
        return date
    }

    private static func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = dateFormat
        formatter.isLenient = false
        return formatter
    }
}

private struct IOSProviderConsentWireObjectReader {
    let object: [String: Any]

    func string(_ key: String) throws -> String {
        guard let value = object[key] as? String else {
            throw IOSProviderConsentWireCodecError.invalidRecord
        }
        return value
    }

    func integer64(_ key: String) throws -> Int64 {
        guard let value = object[key] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              !Self.isFloatingPoint(value),
              let integer = Int64(value.stringValue) else {
            throw IOSProviderConsentWireCodecError.invalidRecord
        }
        return integer
    }

    private static func isFloatingPoint(_ number: NSNumber) -> Bool {
        let type = String(cString: number.objCType)
        return type == "f" || type == "d"
    }
}

private struct IOSProviderConsentWireV1: Encodable {
    let schemaVersion = 1
    let epochID: String
    let revision: Int64
    let disclosureVersion: Int64
    let state: String
    let decisionAt: String
}
