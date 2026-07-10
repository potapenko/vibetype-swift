import Foundation

enum BoundedJSONMemberValidationError: Error, Equatable, Sendable {
    case inputTooLarge
    case malformedJSON
    case duplicateObjectMember
    case resourceLimitExceeded
}

struct BoundedJSONMemberValidationLimits: Equatable, Sendable {
    static func metadataFile(maximumInputByteCount: Int) -> Self {
        Self(
            maximumInputByteCount: maximumInputByteCount,
            maximumDecodedValueStringByteCount: maximumInputByteCount
        )
    }

    let maximumInputByteCount: Int
    let maximumNestingDepth: Int
    let maximumMembersPerObject: Int
    let maximumTotalObjectMembers: Int
    let maximumElementsPerArray: Int
    let maximumTotalValues: Int
    let maximumDecodedKeyByteCount: Int
    let maximumDecodedValueStringByteCount: Int
    let maximumNumberTokenByteCount: Int

    init(
        maximumInputByteCount: Int,
        maximumNestingDepth: Int = 64,
        maximumMembersPerObject: Int = 1_024,
        maximumTotalObjectMembers: Int = 262_144,
        maximumElementsPerArray: Int = 65_536,
        maximumTotalValues: Int = 524_288,
        maximumDecodedKeyByteCount: Int = 4_096,
        maximumDecodedValueStringByteCount: Int = Int.max,
        maximumNumberTokenByteCount: Int = 256
    ) {
        self.maximumInputByteCount = maximumInputByteCount
        self.maximumNestingDepth = maximumNestingDepth
        self.maximumMembersPerObject = maximumMembersPerObject
        self.maximumTotalObjectMembers = maximumTotalObjectMembers
        self.maximumElementsPerArray = maximumElementsPerArray
        self.maximumTotalValues = maximumTotalValues
        self.maximumDecodedKeyByteCount = maximumDecodedKeyByteCount
        self.maximumDecodedValueStringByteCount =
            maximumDecodedValueStringByteCount
        self.maximumNumberTokenByteCount = maximumNumberTokenByteCount
    }
}

/// Performs a bounded structural pass before Foundation collapses JSON objects
/// into dictionaries. Member identity uses Swift `String` equality over the
/// decoded UTF-8 scalars, matching the dictionary representation consumed by
/// the repositories. JSON escape and Unicode canonical equivalence are both
/// detected without case folding or compatibility normalization.
enum BoundedJSONMemberValidator {
    private static let absoluteMaximumNestingDepth = 64

    static func validate(
        _ data: Data,
        limits: BoundedJSONMemberValidationLimits
    ) throws {
        guard limits.maximumInputByteCount >= 0,
              limits.maximumNestingDepth >= 0,
              limits.maximumMembersPerObject >= 0,
              limits.maximumTotalObjectMembers >= 0,
              limits.maximumElementsPerArray >= 0,
              limits.maximumTotalValues >= 0,
              limits.maximumDecodedKeyByteCount >= 0,
              limits.maximumDecodedValueStringByteCount >= 0,
              limits.maximumNumberTokenByteCount >= 0,
              limits.maximumNestingDepth <= absoluteMaximumNestingDepth else {
            throw BoundedJSONMemberValidationError.resourceLimitExceeded
        }
        guard data.count <= limits.maximumInputByteCount else {
            throw BoundedJSONMemberValidationError.inputTooLarge
        }

        var parser = Parser(bytes: ContiguousArray(data), limits: limits)
        try parser.parseDocument()
    }
}

private struct Parser {
    private static let quotationMark: UInt8 = 0x22
    private static let reverseSolidus: UInt8 = 0x5C

    let bytes: ContiguousArray<UInt8>
    let limits: BoundedJSONMemberValidationLimits

    private var index = 0
    private var totalObjectMemberCount = 0
    private var totalValueCount = 0

    init(
        bytes: ContiguousArray<UInt8>,
        limits: BoundedJSONMemberValidationLimits
    ) {
        self.bytes = bytes
        self.limits = limits
    }

    mutating func parseDocument() throws {
        skipWhitespace()
        try parseValue(containerDepth: 0)
        skipWhitespace()
        guard index == bytes.count else {
            throw BoundedJSONMemberValidationError.malformedJSON
        }
    }

    private mutating func parseValue(containerDepth: Int) throws {
        skipWhitespace()
        try registerValue()

        guard let byte = currentByte else {
            throw BoundedJSONMemberValidationError.malformedJSON
        }

        switch byte {
        case 0x7B:
            guard containerDepth < limits.maximumNestingDepth else {
                throw BoundedJSONMemberValidationError.resourceLimitExceeded
            }
            try parseObject(containerDepth: containerDepth + 1)

        case 0x5B:
            guard containerDepth < limits.maximumNestingDepth else {
                throw BoundedJSONMemberValidationError.resourceLimitExceeded
            }
            try parseArray(containerDepth: containerDepth + 1)

        case Self.quotationMark:
            _ = try parseString(
                collectDecodedBytes: false,
                maximumDecodedByteCount:
                    limits.maximumDecodedValueStringByteCount
            )

        case 0x74:
            try consumeLiteral([0x74, 0x72, 0x75, 0x65])

        case 0x66:
            try consumeLiteral([0x66, 0x61, 0x6C, 0x73, 0x65])

        case 0x6E:
            try consumeLiteral([0x6E, 0x75, 0x6C, 0x6C])

        case 0x2D, 0x30...0x39:
            try parseNumber()

        default:
            throw BoundedJSONMemberValidationError.malformedJSON
        }
    }

    private mutating func parseObject(containerDepth: Int) throws {
        try consume(0x7B)
        skipWhitespace()
        if consumeIfPresent(0x7D) {
            return
        }

        var memberNames = Set<String>()
        var memberCount = 0

        while true {
            guard currentByte == Self.quotationMark else {
                throw BoundedJSONMemberValidationError.malformedJSON
            }
            guard let memberNameBytes = try parseString(
                collectDecodedBytes: true,
                maximumDecodedByteCount: limits.maximumDecodedKeyByteCount
            ) else {
                throw BoundedJSONMemberValidationError.malformedJSON
            }
            let memberName = String(decoding: memberNameBytes, as: UTF8.self)
            try registerObjectMember(localCount: &memberCount)
            guard memberNames.insert(memberName).inserted else {
                throw BoundedJSONMemberValidationError.duplicateObjectMember
            }

            skipWhitespace()
            try consume(0x3A)
            try parseValue(containerDepth: containerDepth)
            skipWhitespace()

            if consumeIfPresent(0x7D) {
                return
            }
            try consume(0x2C)
            skipWhitespace()
        }
    }

    private mutating func parseArray(containerDepth: Int) throws {
        try consume(0x5B)
        skipWhitespace()
        if consumeIfPresent(0x5D) {
            return
        }

        var elementCount = 0
        while true {
            guard elementCount < limits.maximumElementsPerArray else {
                throw BoundedJSONMemberValidationError.resourceLimitExceeded
            }
            elementCount += 1
            try parseValue(containerDepth: containerDepth)
            skipWhitespace()

            if consumeIfPresent(0x5D) {
                return
            }
            try consume(0x2C)
            skipWhitespace()
        }
    }

    private mutating func parseString(
        collectDecodedBytes: Bool,
        maximumDecodedByteCount: Int
    ) throws -> [UInt8]? {
        try consume(Self.quotationMark)
        var decodedBytes: [UInt8]? = collectDecodedBytes ? [] : nil
        var decodedByteCount = 0
        if collectDecodedBytes {
            decodedBytes?.reserveCapacity(
                min(32, maximumDecodedByteCount)
            )
        }

        while let byte = currentByte {
            switch byte {
            case Self.quotationMark:
                index += 1
                return decodedBytes

            case Self.reverseSolidus:
                index += 1
                try parseEscape(
                    decodedBytes: &decodedBytes,
                    decodedByteCount: &decodedByteCount,
                    maximumDecodedByteCount: maximumDecodedByteCount
                )

            case 0x00...0x1F:
                throw BoundedJSONMemberValidationError.malformedJSON

            default:
                let scalarBytes = try consumeUTF8Scalar()
                try appendDecoded(
                    bytes[scalarBytes],
                    to: &decodedBytes,
                    decodedByteCount: &decodedByteCount,
                    maximumDecodedByteCount: maximumDecodedByteCount
                )
            }
        }

        throw BoundedJSONMemberValidationError.malformedJSON
    }

    private mutating func parseEscape(
        decodedBytes: inout [UInt8]?,
        decodedByteCount: inout Int,
        maximumDecodedByteCount: Int
    ) throws {
        guard let escape = currentByte else {
            throw BoundedJSONMemberValidationError.malformedJSON
        }
        index += 1

        switch escape {
        case 0x22:
            try appendDecoded(
                0x22,
                to: &decodedBytes,
                decodedByteCount: &decodedByteCount,
                maximumDecodedByteCount: maximumDecodedByteCount
            )
        case 0x5C:
            try appendDecoded(
                0x5C,
                to: &decodedBytes,
                decodedByteCount: &decodedByteCount,
                maximumDecodedByteCount: maximumDecodedByteCount
            )
        case 0x2F:
            try appendDecoded(
                0x2F,
                to: &decodedBytes,
                decodedByteCount: &decodedByteCount,
                maximumDecodedByteCount: maximumDecodedByteCount
            )
        case 0x62:
            try appendDecoded(
                0x08,
                to: &decodedBytes,
                decodedByteCount: &decodedByteCount,
                maximumDecodedByteCount: maximumDecodedByteCount
            )
        case 0x66:
            try appendDecoded(
                0x0C,
                to: &decodedBytes,
                decodedByteCount: &decodedByteCount,
                maximumDecodedByteCount: maximumDecodedByteCount
            )
        case 0x6E:
            try appendDecoded(
                0x0A,
                to: &decodedBytes,
                decodedByteCount: &decodedByteCount,
                maximumDecodedByteCount: maximumDecodedByteCount
            )
        case 0x72:
            try appendDecoded(
                0x0D,
                to: &decodedBytes,
                decodedByteCount: &decodedByteCount,
                maximumDecodedByteCount: maximumDecodedByteCount
            )
        case 0x74:
            try appendDecoded(
                0x09,
                to: &decodedBytes,
                decodedByteCount: &decodedByteCount,
                maximumDecodedByteCount: maximumDecodedByteCount
            )
        case 0x75:
            let scalar = try parseUnicodeEscape()
            try appendDecodedUTF8(
                scalar,
                to: &decodedBytes,
                decodedByteCount: &decodedByteCount,
                maximumDecodedByteCount: maximumDecodedByteCount
            )
        default:
            throw BoundedJSONMemberValidationError.malformedJSON
        }
    }

    private mutating func parseUnicodeEscape() throws -> UInt32 {
        let firstCodeUnit = try parseHexCodeUnit()
        let scalarValue: UInt32

        switch firstCodeUnit {
        case 0xD800...0xDBFF:
            guard currentByte == Self.reverseSolidus,
                  byte(at: index + 1) == 0x75 else {
                throw BoundedJSONMemberValidationError.malformedJSON
            }
            index += 2
            let secondCodeUnit = try parseHexCodeUnit()
            guard (0xDC00...0xDFFF).contains(secondCodeUnit) else {
                throw BoundedJSONMemberValidationError.malformedJSON
            }
            scalarValue = 0x10000
                + (UInt32(firstCodeUnit - 0xD800) << 10)
                + UInt32(secondCodeUnit - 0xDC00)

        case 0xDC00...0xDFFF:
            throw BoundedJSONMemberValidationError.malformedJSON

        default:
            scalarValue = UInt32(firstCodeUnit)
        }

        return scalarValue
    }

    private mutating func parseHexCodeUnit() throws -> UInt16 {
        guard index <= bytes.count - 4 else {
            throw BoundedJSONMemberValidationError.malformedJSON
        }

        var value: UInt16 = 0
        for _ in 0..<4 {
            guard let nibble = hexValue(bytes[index]) else {
                throw BoundedJSONMemberValidationError.malformedJSON
            }
            value = (value << 4) | UInt16(nibble)
            index += 1
        }
        return value
    }

    private mutating func consumeUTF8Scalar() throws -> Range<Int> {
        guard let first = currentByte else {
            throw BoundedJSONMemberValidationError.malformedJSON
        }

        let startIndex = index
        let length: Int
        let secondRange: ClosedRange<UInt8>
        switch first {
        case 0x20...0x7F:
            length = 1
            secondRange = 0...0
        case 0xC2...0xDF:
            length = 2
            secondRange = 0x80...0xBF
        case 0xE0:
            length = 3
            secondRange = 0xA0...0xBF
        case 0xE1...0xEC, 0xEE...0xEF:
            length = 3
            secondRange = 0x80...0xBF
        case 0xED:
            length = 3
            secondRange = 0x80...0x9F
        case 0xF0:
            length = 4
            secondRange = 0x90...0xBF
        case 0xF1...0xF3:
            length = 4
            secondRange = 0x80...0xBF
        case 0xF4:
            length = 4
            secondRange = 0x80...0x8F
        default:
            throw BoundedJSONMemberValidationError.malformedJSON
        }

        guard index <= bytes.count - length else {
            throw BoundedJSONMemberValidationError.malformedJSON
        }
        if length >= 2 {
            guard secondRange.contains(bytes[index + 1]) else {
                throw BoundedJSONMemberValidationError.malformedJSON
            }
        }
        if length >= 3 {
            guard (0x80...0xBF).contains(bytes[index + 2]) else {
                throw BoundedJSONMemberValidationError.malformedJSON
            }
        }
        if length == 4 {
            guard (0x80...0xBF).contains(bytes[index + 3]) else {
                throw BoundedJSONMemberValidationError.malformedJSON
            }
        }

        index += length
        return startIndex..<index
    }

    private mutating func parseNumber() throws {
        let startIndex = index

        if consumeIfPresent(0x2D) {
            try enforceNumberLimit(startingAt: startIndex)
        }

        guard let firstDigit = currentByte else {
            throw BoundedJSONMemberValidationError.malformedJSON
        }
        if firstDigit == 0x30 {
            index += 1
            try enforceNumberLimit(startingAt: startIndex)
            if let next = currentByte, (0x30...0x39).contains(next) {
                throw BoundedJSONMemberValidationError.malformedJSON
            }
        } else if (0x31...0x39).contains(firstDigit) {
            repeat {
                index += 1
                try enforceNumberLimit(startingAt: startIndex)
            } while currentByte.map({ (0x30...0x39).contains($0) }) == true
        } else {
            throw BoundedJSONMemberValidationError.malformedJSON
        }

        if consumeIfPresent(0x2E) {
            try enforceNumberLimit(startingAt: startIndex)
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw BoundedJSONMemberValidationError.malformedJSON
            }
            repeat {
                index += 1
                try enforceNumberLimit(startingAt: startIndex)
            } while currentByte.map({ (0x30...0x39).contains($0) }) == true
        }

        if currentByte == 0x65 || currentByte == 0x45 {
            index += 1
            try enforceNumberLimit(startingAt: startIndex)
            if currentByte == 0x2B || currentByte == 0x2D {
                index += 1
                try enforceNumberLimit(startingAt: startIndex)
            }
            guard currentByte.map({ (0x30...0x39).contains($0) }) == true else {
                throw BoundedJSONMemberValidationError.malformedJSON
            }
            repeat {
                index += 1
                try enforceNumberLimit(startingAt: startIndex)
            } while currentByte.map({ (0x30...0x39).contains($0) }) == true
        }
    }

    private mutating func consumeLiteral(_ literal: [UInt8]) throws {
        guard index <= bytes.count - literal.count else {
            throw BoundedJSONMemberValidationError.malformedJSON
        }
        for (offset, expected) in literal.enumerated() {
            guard bytes[index + offset] == expected else {
                throw BoundedJSONMemberValidationError.malformedJSON
            }
        }
        index += literal.count
    }

    private mutating func registerValue() throws {
        guard totalValueCount < limits.maximumTotalValues else {
            throw BoundedJSONMemberValidationError.resourceLimitExceeded
        }
        totalValueCount += 1
    }

    private mutating func registerObjectMember(localCount: inout Int) throws {
        guard localCount < limits.maximumMembersPerObject,
              totalObjectMemberCount < limits.maximumTotalObjectMembers else {
            throw BoundedJSONMemberValidationError.resourceLimitExceeded
        }
        localCount += 1
        totalObjectMemberCount += 1
    }

    private func enforceNumberLimit(startingAt startIndex: Int) throws {
        guard index - startIndex <= limits.maximumNumberTokenByteCount else {
            throw BoundedJSONMemberValidationError.resourceLimitExceeded
        }
    }

    private func appendDecoded(
        _ byte: UInt8,
        to decodedBytes: inout [UInt8]?,
        decodedByteCount: inout Int,
        maximumDecodedByteCount: Int
    ) throws {
        try registerDecodedBytes(
            1,
            decodedByteCount: &decodedByteCount,
            maximumDecodedByteCount: maximumDecodedByteCount
        )
        decodedBytes?.append(byte)
    }

    private func appendDecoded<Bytes: Collection>(
        _ newBytes: Bytes,
        to decodedBytes: inout [UInt8]?,
        decodedByteCount: inout Int,
        maximumDecodedByteCount: Int
    ) throws where Bytes.Element == UInt8 {
        try registerDecodedBytes(
            newBytes.count,
            decodedByteCount: &decodedByteCount,
            maximumDecodedByteCount: maximumDecodedByteCount
        )
        decodedBytes?.append(contentsOf: newBytes)
    }

    private func appendDecodedUTF8(
        _ scalar: UInt32,
        to decodedBytes: inout [UInt8]?,
        decodedByteCount: inout Int,
        maximumDecodedByteCount: Int
    ) throws {
        let additionalByteCount: Int
        switch scalar {
        case 0...0x7F:
            additionalByteCount = 1
        case 0x80...0x7FF:
            additionalByteCount = 2
        case 0x800...0xFFFF:
            additionalByteCount = 3
        default:
            additionalByteCount = 4
        }
        try registerDecodedBytes(
            additionalByteCount,
            decodedByteCount: &decodedByteCount,
            maximumDecodedByteCount: maximumDecodedByteCount
        )

        guard decodedBytes != nil else { return }

        switch scalar {
        case 0...0x7F:
            decodedBytes?.append(UInt8(scalar))
        case 0x80...0x7FF:
            decodedBytes?.append(UInt8(0xC0 | (scalar >> 6)))
            decodedBytes?.append(UInt8(0x80 | (scalar & 0x3F)))
        case 0x800...0xFFFF:
            decodedBytes?.append(UInt8(0xE0 | (scalar >> 12)))
            decodedBytes?.append(UInt8(0x80 | ((scalar >> 6) & 0x3F)))
            decodedBytes?.append(UInt8(0x80 | (scalar & 0x3F)))
        default:
            decodedBytes?.append(UInt8(0xF0 | (scalar >> 18)))
            decodedBytes?.append(UInt8(0x80 | ((scalar >> 12) & 0x3F)))
            decodedBytes?.append(UInt8(0x80 | ((scalar >> 6) & 0x3F)))
            decodedBytes?.append(UInt8(0x80 | (scalar & 0x3F)))
        }
    }

    private func registerDecodedBytes(
        _ additionalByteCount: Int,
        decodedByteCount: inout Int,
        maximumDecodedByteCount: Int
    ) throws {
        guard additionalByteCount
                <= maximumDecodedByteCount - decodedByteCount else {
            throw BoundedJSONMemberValidationError.resourceLimitExceeded
        }
        decodedByteCount += additionalByteCount
    }

    private mutating func consume(_ expected: UInt8) throws {
        guard currentByte == expected else {
            throw BoundedJSONMemberValidationError.malformedJSON
        }
        index += 1
    }

    private mutating func consumeIfPresent(_ expected: UInt8) -> Bool {
        guard currentByte == expected else {
            return false
        }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while let byte = currentByte,
              byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
        }
    }

    private var currentByte: UInt8? {
        byte(at: index)
    }

    private func byte(at offset: Int) -> UInt8? {
        guard offset >= 0, offset < bytes.count else {
            return nil
        }
        return bytes[offset]
    }

    private func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39:
            byte - 0x30
        case 0x41...0x46:
            byte - 0x41 + 10
        case 0x61...0x66:
            byte - 0x61 + 10
        default:
            nil
        }
    }

}
