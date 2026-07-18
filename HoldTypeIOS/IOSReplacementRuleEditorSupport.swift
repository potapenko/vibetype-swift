import Foundation
import HoldTypeDomain

nonisolated struct IOSReplacementRuleReference: Equatable, Sendable {
    let expected: TextReplacementRule
}

nonisolated struct IOSReplacementRuleEditorDraft: Equatable, Sendable {
    let id: UUID
    var search: String
    var replacement: String

    init(id: UUID) {
        self.id = id
        search = ""
        replacement = ""
    }

    init(rule: TextReplacementRule) {
        id = rule.id
        search = rule.search
        replacement = rule.replacement
    }

    var hasAnyInput: Bool {
        !search.isEmpty || !replacement.isEmpty
    }

    func candidate(isEnabled: Bool) -> TextReplacementRule {
        TextReplacementRule(
            id: id,
            search: search,
            replacement: replacement,
            isEnabled: isEnabled
        )
    }
}

nonisolated enum IOSReplacementRuleEditorMode: Equatable, Sendable {
    case add(UUID)
    case edit(UUID)

    var id: UUID {
        switch self {
        case .add(let id), .edit(let id): id
        }
    }

    var isNew: Bool {
        if case .add = self { return true }
        return false
    }
}

nonisolated enum IOSReplacementRuleDraftValidation: Equatable, Sendable {
    case valid
    case missingSearch

    static func resolve(
        mode: IOSReplacementRuleEditorMode,
        draft: IOSReplacementRuleEditorDraft
    ) -> Self {
        switch mode {
        case .add:
            draft.candidate(isEnabled: true).hasSearchText
                ? .valid
                : .missingSearch
        case .edit:
            .valid
        }
    }
}

enum IOSReplacementRuleEditorPhase: Equatable {
    case idle
    case saving
    case saved
    case saveFailed
    case changedElsewhere
    case deletedElsewhere
    case invalid
}

nonisolated struct IOSReplacementRuleSaveRequest: Equatable, Sendable {
    let mutation: IOSLibraryMutation
    let ruleID: UUID
}

struct IOSReplacementRuleEditorSession: Equatable {
    let mode: IOSReplacementRuleEditorMode
    private(set) var baseline: TextReplacementRule?
    private(set) var latest: TextReplacementRule?
    private(set) var draft: IOSReplacementRuleEditorDraft
    private(set) var phase = IOSReplacementRuleEditorPhase.idle

    init(newRuleID: UUID) {
        mode = .add(newRuleID)
        baseline = nil
        latest = nil
        draft = IOSReplacementRuleEditorDraft(id: newRuleID)
    }

    init(rule: TextReplacementRule) {
        mode = .edit(rule.id)
        baseline = rule
        latest = rule
        draft = IOSReplacementRuleEditorDraft(rule: rule)
    }

    var isDirty: Bool {
        draft != baselineDraft
    }

    var isSaving: Bool { phase == .saving }

    var canReloadLatest: Bool {
        !mode.isNew && phase == .changedElsewhere && latest != nil
    }

    var canReplaceLatest: Bool {
        canReloadLatest && isDirty
    }

    var validation: IOSReplacementRuleDraftValidation {
        IOSReplacementRuleDraftValidation.resolve(mode: mode, draft: draft)
    }

    mutating func set(
        _ value: String,
        at keyPath: WritableKeyPath<IOSReplacementRuleEditorDraft, String>
    ) {
        guard !isSaving, draft[keyPath: keyPath] != value else { return }
        draft[keyPath: keyPath] = value
        if !isDirty {
            phase = .idle
        } else {
            switch phase {
            case .saved, .invalid:
                phase = .idle
            case .idle, .saving, .saveFailed, .changedElsewhere,
                    .deletedElsewhere:
                break
            }
        }
    }

    mutating func beginSave(
        replacingLatest: Bool = false
    ) -> IOSReplacementRuleSaveRequest? {
        guard isDirty, !isSaving,
              phase != .deletedElsewhere,
              validation == .valid else {
            return nil
        }

        let mutation: IOSLibraryMutation
        switch mode {
        case .add:
            guard phase != .changedElsewhere else { return nil }
            mutation = .replacementRules(
                .add(draft.candidate(isEnabled: true))
            )
        case .edit:
            if phase == .changedElsewhere, !replacingLatest {
                return nil
            }
            let expected = replacingLatest ? latest : baseline
            guard let expected else { return nil }
            mutation = .replacementRules(
                .update(
                    expected: expected,
                    requested: draft.candidate(
                        isEnabled: expected.isEnabled
                    )
                )
            )
        }

        phase = .saving
        return IOSReplacementRuleSaveRequest(
            mutation: mutation,
            ruleID: mode.id
        )
    }

    mutating func observeDurableRule(_ rule: TextReplacementRule?) {
        latest = rule
        guard !isSaving else { return }

        switch mode {
        case .add:
            guard let rule else { return }
            if IOSReplacementRuleEditorDraft(rule: rule) == draft {
                adopt(rule, phase: .saved)
            } else {
                phase = .changedElsewhere
            }
        case .edit:
            guard let rule else {
                phase = .deletedElsewhere
                return
            }
            guard rule != baseline else {
                if phase == .deletedElsewhere, isDirty {
                    phase = .changedElsewhere
                } else if !isDirty,
                          phase == .changedElsewhere
                            || phase == .deletedElsewhere {
                    phase = .idle
                }
                return
            }
            let incomingDraft = IOSReplacementRuleEditorDraft(rule: rule)
            if !isDirty {
                adopt(rule, phase: .idle)
            } else if incomingDraft == draft {
                adopt(rule, phase: .saved)
            } else {
                markChangedElsewhere(rule)
            }
        }
    }

    mutating func reloadLatest() {
        guard let latest else { return }
        adopt(latest, phase: .idle)
    }

    mutating func commitSucceeded(
        returnedRule: TextReplacementRule?,
        currentRule: TextReplacementRule?
    ) {
        latest = currentRule
        guard let currentRule else {
            latest = nil
            phase = .deletedElsewhere
            return
        }
        guard let returnedRule else {
            markChangedElsewhere(currentRule)
            return
        }

        let currentDraft = IOSReplacementRuleEditorDraft(rule: currentRule)
        let returnedDraft = IOSReplacementRuleEditorDraft(rule: returnedRule)
        let draftOwnedFieldsMatch = currentDraft == returnedDraft
        guard currentRule == returnedRule || draftOwnedFieldsMatch else {
            markChangedElsewhere(currentRule)
            return
        }
        adopt(currentRule, phase: .saved)
    }

    mutating func commitFailed(
        currentRule: TextReplacementRule?,
        forceNotSaved: Bool = false
    ) {
        let previousBaseline = baseline
        latest = currentRule
        switch mode {
        case .add:
            if let currentRule {
                markChangedElsewhere(currentRule)
                return
            }
        case .edit:
            guard let currentRule else {
                phase = .deletedElsewhere
                return
            }
            if currentRule != previousBaseline {
                markChangedElsewhere(currentRule)
                return
            }
            baseline = currentRule
        }
        phase = isDirty || forceNotSaved ? .saveFailed : .idle
    }

    mutating func completeWithoutCommit(
        disposition: IOSLibraryMutationDisposition,
        returnedRule: TextReplacementRule?,
        currentRule: TextReplacementRule?
    ) {
        latest = currentRule
        switch disposition {
        case .unchanged:
            commitSucceeded(
                returnedRule: returnedRule,
                currentRule: currentRule
            )
        case .targetMissing, .conflict:
            if let currentRule {
                markChangedElsewhere(currentRule)
            } else {
                phase = .deletedElsewhere
            }
        case .duplicate, .invalid:
            if let currentRule,
               mode.isNew || currentRule != baseline {
                markChangedElsewhere(currentRule)
            } else {
                phase = .invalid
            }
        case .committed:
            commitSucceeded(
                returnedRule: returnedRule,
                currentRule: currentRule
            )
        }
    }

    mutating func discard() {
        draft = baselineDraft
        phase = .idle
    }

    private var baselineDraft: IOSReplacementRuleEditorDraft {
        if let baseline {
            return IOSReplacementRuleEditorDraft(rule: baseline)
        }
        return IOSReplacementRuleEditorDraft(id: mode.id)
    }

    private mutating func adopt(
        _ rule: TextReplacementRule,
        phase: IOSReplacementRuleEditorPhase
    ) {
        baseline = rule
        latest = rule
        draft = IOSReplacementRuleEditorDraft(rule: rule)
        self.phase = phase
    }

    private mutating func markChangedElsewhere(
        _ rule: TextReplacementRule
    ) {
        latest = rule
        if case .edit = mode {
            baseline = rule
        }
        phase = .changedElsewhere
    }
}

nonisolated enum IOSReplacementRulesMoveDirection: Equatable, Sendable {
    case up
    case down
}

nonisolated struct IOSReplacementRulesOrderRequest: Equatable, Sendable {
    let expected: [UUID]
    let requested: [UUID]

    init?(
        expected: [UUID],
        moving offsets: IndexSet,
        to destination: Int
    ) {
        guard !offsets.isEmpty,
              offsets.allSatisfy(expected.indices.contains),
              (0...expected.count).contains(destination) else {
            return nil
        }

        let movingIDs = offsets.map { expected[$0] }
        let offsetSet = Set(offsets)
        var remaining = expected.enumerated().compactMap { index, id in
            offsetSet.contains(index) ? nil : id
        }
        let removedBeforeDestination = offsets.filter {
            $0 < destination
        }.count
        let insertionIndex = destination - removedBeforeDestination
        guard remaining.indices.contains(insertionIndex)
                || insertionIndex == remaining.endIndex else {
            return nil
        }
        remaining.insert(contentsOf: movingIDs, at: insertionIndex)

        self.expected = expected
        requested = remaining
    }

    init?(
        expected: [UUID],
        moving id: UUID,
        direction: IOSReplacementRulesMoveDirection
    ) {
        guard let index = expected.firstIndex(of: id) else { return nil }
        let destination: Int
        switch direction {
        case .up:
            guard index > expected.startIndex else { return nil }
            destination = index - 1
        case .down:
            guard index < expected.index(before: expected.endIndex) else {
                return nil
            }
            destination = index + 2
        }
        self.init(
            expected: expected,
            moving: IndexSet(integer: index),
            to: destination
        )
    }

    var mutation: IOSLibraryMutation {
        .replacementRules(
            .reorder(expected: expected, requested: requested)
        )
    }
}

nonisolated struct IOSReplacementRulesPendingOrder: Equatable, Sendable {
    let ruleIDs: [UUID]

    init(request: IOSReplacementRulesOrderRequest) {
        ruleIDs = request.requested
    }

    func orderedRules(
        from durableRules: [TextReplacementRule]
    ) -> [TextReplacementRule]? {
        let durableIDs = durableRules.map(\.id)
        guard Set(durableIDs).count == durableIDs.count,
              Set(ruleIDs).count == ruleIDs.count,
              Set(durableIDs) == Set(ruleIDs) else {
            return nil
        }
        let rulesByID = Dictionary(
            uniqueKeysWithValues: durableRules.map { ($0.id, $0) }
        )
        let ordered = ruleIDs.compactMap { rulesByID[$0] }
        return ordered.count == durableRules.count ? ordered : nil
    }
}

enum IOSReplacementRuleRuntimeStatus: Equatable {
    case active
    case off
    case inactiveEmptySearch

    init(rule: TextReplacementRule) {
        if !rule.hasSearchText {
            self = .inactiveEmptySearch
        } else {
            self = rule.isEnabled ? .active : .off
        }
    }

    var title: String {
        switch self {
        case .active: "Active"
        case .off: "Off"
        case .inactiveEmptySearch: "Inactive — empty search"
        }
    }

    var systemImage: String {
        switch self {
        case .active: "checkmark.circle.fill"
        case .off: "pause.circle"
        case .inactiveEmptySearch: "exclamationmark.circle"
        }
    }
}

enum IOSReplacementRulesNotice: Equatable {
    case saved
    case deleted
    case reordered
    case changedElsewhere
    case invalid
    case notSaved
}

enum IOSReplacementRulesPresentation {
    static func summary(_ rules: [TextReplacementRule]) -> String {
        guard !rules.isEmpty else { return "0 custom rules" }
        let activeCount = rules.count {
            $0.isEnabled && $0.hasSearchText
        }
        let ruleLabel = rules.count == 1 ? "custom rule" : "custom rules"
        return "\(rules.count) \(ruleLabel) · \(activeCount) active"
    }
}

extension IOSReplacementRuleReference: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSReplacementRuleReference(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSReplacementRuleEditorDraft: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSReplacementRuleEditorDraft(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSReplacementRuleEditorMode: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSReplacementRuleEditorMode(content-free)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSReplacementRuleDraftValidation: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSReplacementRuleDraftValidation(content-free)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSReplacementRuleEditorPhase: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSReplacementRuleEditorPhase(content-free)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSReplacementRuleSaveRequest: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSReplacementRuleSaveRequest(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSReplacementRuleEditorSession: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSReplacementRuleEditorSession(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSReplacementRulesMoveDirection: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSReplacementRulesMoveDirection(content-free)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSReplacementRulesOrderRequest: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSReplacementRulesOrderRequest(content-free)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSReplacementRulesPendingOrder: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSReplacementRulesPendingOrder(content-free)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSReplacementRuleRuntimeStatus: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSReplacementRuleRuntimeStatus(content-free)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSReplacementRulesNotice: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    var description: String { "IOSReplacementRulesNotice(content-free)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
