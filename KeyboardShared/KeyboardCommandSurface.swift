//
//  KeyboardCommandSurface.swift
//  HoldType
//
//  Created by Codex on 7/13/26.
//

import Foundation

enum KeyboardTopRailStatus: String, CaseIterable, Equatable, Sendable {
    case ready = "Ready"
    case enableFullAccess = "Enable Full Access"
    case listening = "Listening…"
    case processing = "Processing…"
    case openHoldType = "Open HoldType"
    case tryAgain = "Try Again"
    case openSettings = "Open Settings"

    var accessibilityAnnouncement: String? {
        switch self {
        case .ready:
            nil
        case .enableFullAccess,
             .listening,
             .processing,
             .openHoldType,
             .tryAgain,
             .openSettings:
            rawValue
        }
    }
}

enum KeyboardCursorDirection: Equatable, Sendable {
    case backward
    case forward
}

struct KeyboardCursorMovement: Equatable, Sendable {
    let direction: KeyboardCursorDirection
    let characterCount: Int

    init(direction: KeyboardCursorDirection, characterCount: Int) {
        precondition(characterCount > 0)
        self.direction = direction
        self.characterCount = characterCount
    }

    var characterOffset: Int {
        switch direction {
        case .backward:
            return -characterCount
        case .forward:
            return characterCount
        }
    }
}

/// Converts incremental horizontal drag distance into bounded logical cursor movement.
struct KeyboardCursorDragAccumulator: Equatable, Sendable {
    let pointsPerCharacter: Double
    let maximumCharactersPerUpdate: Int

    private(set) var accumulatedPoints = 0.0

    init(
        pointsPerCharacter: Double = 12,
        maximumCharactersPerUpdate: Int = 12
    ) {
        precondition(pointsPerCharacter.isFinite && pointsPerCharacter > 0)
        precondition(maximumCharactersPerUpdate > 0)
        self.pointsPerCharacter = pointsPerCharacter
        self.maximumCharactersPerUpdate = maximumCharactersPerUpdate
    }

    mutating func consume(horizontalDelta: Double) -> KeyboardCursorMovement? {
        guard horizontalDelta.isFinite else {
            return nil
        }

        let totalPoints = accumulatedPoints + horizontalDelta
        guard totalPoints.isFinite else {
            accumulatedPoints = 0
            return nil
        }

        let unboundedCharacters = totalPoints / pointsPerCharacter
        let boundedCharacterOffset: Int

        if unboundedCharacters >= Double(maximumCharactersPerUpdate) {
            boundedCharacterOffset = maximumCharactersPerUpdate
        } else if unboundedCharacters <= -Double(maximumCharactersPerUpdate) {
            boundedCharacterOffset = -maximumCharactersPerUpdate
        } else {
            boundedCharacterOffset = Int(unboundedCharacters.rounded(.towardZero))
        }

        guard boundedCharacterOffset != 0 else {
            accumulatedPoints = totalPoints
            return nil
        }

        // Discard movement beyond the per-update cap rather than queueing a large jump.
        accumulatedPoints = totalPoints.truncatingRemainder(dividingBy: pointsPerCharacter)
        let direction: KeyboardCursorDirection = boundedCharacterOffset > 0
            ? .forward
            : .backward
        return KeyboardCursorMovement(
            direction: direction,
            characterCount: abs(boundedCharacterOffset)
        )
    }

    mutating func reset() {
        accumulatedPoints = 0
    }
}

/// Timing values for touch-down deletion followed by bounded accelerated repeat.
struct KeyboardDeleteRepeatProfile: Equatable, Sendable {
    let initialDelay: TimeInterval
    let slowestInterval: TimeInterval
    let fastestInterval: TimeInterval
    let accelerationPerRepeat: TimeInterval

    init(
        initialDelay: TimeInterval = 0.42,
        slowestInterval: TimeInterval = 0.085,
        fastestInterval: TimeInterval = 0.045,
        accelerationPerRepeat: TimeInterval = 0.002
    ) {
        precondition(initialDelay >= 0)
        precondition(slowestInterval >= fastestInterval)
        precondition(fastestInterval > 0)
        precondition(accelerationPerRepeat >= 0)
        self.initialDelay = initialDelay
        self.slowestInterval = slowestInterval
        self.fastestInterval = fastestInterval
        self.accelerationPerRepeat = accelerationPerRepeat
    }

    func interval(afterCompletedRepeats completedRepeats: Int) -> TimeInterval {
        let boundedCount = max(0, completedRepeats)
        let acceleratedInterval = slowestInterval
            - (Double(boundedCount) * accelerationPerRepeat)
        return max(fastestInterval, acceleratedInterval)
    }
}

/// UIKit maps host return-key traits into this neutral semantic input.
enum KeyboardReturnKeySemantic: CaseIterable, Equatable, Hashable, Sendable {
    case lineBreak
    case go
    case join
    case next
    case route
    case search
    case send
    case done
    case emergencyCall
    case continueAction
}

enum KeyboardReturnKeyPresentation: Equatable, Sendable {
    case returnSymbol
    case title(String)

    init(semantic: KeyboardReturnKeySemantic) {
        switch semantic {
        case .lineBreak:
            self = .returnSymbol
        case .go:
            self = .title("Go")
        case .join:
            self = .title("Join")
        case .next:
            self = .title("Next")
        case .route:
            self = .title("Route")
        case .search:
            self = .title("Search")
        case .send:
            self = .title("Send")
        case .done:
            self = .title("Done")
        case .emergencyCall:
            self = .title("Emergency Call")
        case .continueAction:
            self = .title("Continue")
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .returnSymbol:
            return "Return"
        case let .title(title):
            return title
        }
    }
}

/// Suppresses re-entrant handling while still allowing every later explicit tap.
struct KeyboardInsertionEventGate: Equatable, Sendable {
    private(set) var isHandlingEvent = false

    mutating func beginEvent() -> Bool {
        guard !isHandlingEvent else {
            return false
        }

        isHandlingEvent = true
        return true
    }

    mutating func endEvent() {
        isHandlingEvent = false
    }
}
