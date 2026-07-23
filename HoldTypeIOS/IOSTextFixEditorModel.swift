import Foundation
import HoldTypeDomain
import Observation

/// Main-actor transaction owner for one app-private iOS Fixes catalog.
@MainActor
@Observable
final class IOSTextFixEditorModel {
    typealias StateCallback = @MainActor @Sendable (Bool) -> Void

    private(set) var catalog: TextFixCatalog?
    private(set) var phase = IOSTextFixEditorPhase.notLoaded
    private(set) var failure: IOSTextFixEditorFailure?
    private(set) var activeDraft: IOSTextFixEditorDraft?
    var searchText = ""

    @ObservationIgnored
    private let client: IOSTextFixEditorClient
    @ObservationIgnored
    private let onUnsavedStateChange: StateCallback
    @ObservationIgnored
    private let onBlockingStateChange: StateCallback
    @ObservationIgnored
    private var activeDraftBaseline: IOSTextFixEditorDraft?
    @ObservationIgnored
    private var lastReportedUnsavedState = false
    @ObservationIgnored
    private var lastReportedBlockingState = false

    init(
        client: IOSTextFixEditorClient,
        onUnsavedStateChange: @escaping StateCallback = { _ in },
        onBlockingStateChange: @escaping StateCallback = { _ in }
    ) {
        self.client = client
        self.onUnsavedStateChange = onUnsavedStateChange
        self.onBlockingStateChange = onBlockingStateChange
    }

    var isLoaded: Bool { catalog != nil }

    var isBlockingOperation: Bool {
        phase == .loading || phase == .saving
    }

    var hasUnsavedChanges: Bool {
        guard let activeDraft else { return false }
        guard let activeDraftBaseline else {
            return activeDraft.hasMeaningfulInput
        }
        return activeDraft != activeDraftBaseline
    }

    var activeDraftIsNew: Bool {
        activeDraft != nil && activeDraftBaseline == nil
    }

    var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var filteredActions: [TextFixAction] {
        guard let actions = catalog?.actions else { return [] }
        let query = normalizedSearchText
        guard !query.isEmpty else { return actions }
        return actions.filter { action in
            action.title.localizedStandardContains(query)
                || action.prompt?.localizedStandardContains(query) == true
        }
    }

    var filteredBuiltInActions: [TextFixAction] {
        filteredActions.filter { $0.kind != .customPrompt }
    }

    var filteredCustomActions: [TextFixAction] {
        filteredActions.filter { $0.kind == .customPrompt }
    }

    var canAddCustomAction: Bool {
        guard let catalog else { return false }
        return !isBlockingOperation
            && activeDraft == nil
            && catalog.actions.count < TextFixCatalog.maximumActionCount
    }

    var canSaveActiveDraft: Bool {
        activeDraft?.validation == .valid
            && hasUnsavedChanges
            && !isBlockingOperation
            && catalog != nil
    }

    @discardableResult
    func load() async -> Bool {
        guard !isBlockingOperation else {
            return reject(.operationInFlight)
        }
        guard catalog == nil else { return true }

        phase = .loading
        failure = nil
        publishIntegrationState()
        do {
            let loadedCatalog = try await client.load()
            guard !Task.isCancelled else {
                phase = .notLoaded
                publishIntegrationState()
                return false
            }
            catalog = loadedCatalog
            phase = .ready
            publishIntegrationState()
            return true
        } catch is CancellationError {
            phase = .notLoaded
            publishIntegrationState()
            return false
        } catch {
            phase = .notLoaded
            failure = .loadFailed
            publishIntegrationState()
            return false
        }
    }

    @discardableResult
    func beginNewCustomAction(id: String) -> Bool {
        if activeDraft?.id == id, activeDraftBaseline == nil {
            return true
        }
        guard canAddCustomAction else {
            return reject(
                isBlockingOperation
                    ? .operationInFlight
                    : catalog == nil
                        ? .catalogNotLoaded
                        : .anotherDraftIsOpen
            )
        }
        activeDraft = IOSTextFixEditorDraft(id: id)
        activeDraftBaseline = nil
        clearChangeFailure()
        publishIntegrationState()
        return true
    }

    @discardableResult
    func beginEditingCustomAction(id: String) -> Bool {
        guard !isBlockingOperation else {
            return reject(.operationInFlight)
        }
        if activeDraft?.id == id {
            return true
        }
        guard activeDraft == nil else {
            return reject(.anotherDraftIsOpen)
        }
        guard let action = catalog?.action(id: id) else {
            return reject(catalog == nil ? .catalogNotLoaded : .actionNotFound)
        }
        guard action.kind == .customPrompt else {
            return reject(.builtInReadOnly)
        }
        let draft = IOSTextFixEditorDraft(customAction: action)
        activeDraft = draft
        activeDraftBaseline = draft
        clearChangeFailure()
        publishIntegrationState()
        return true
    }

    @discardableResult
    func updateActiveDraft(_ draft: IOSTextFixEditorDraft) -> Bool {
        guard !isBlockingOperation else {
            return reject(.operationInFlight)
        }
        guard activeDraft?.id == draft.id else {
            return reject(.actionNotFound)
        }
        activeDraft = draft
        clearChangeFailure()
        publishIntegrationState()
        return true
    }

    func discardActiveDraft() {
        guard !isBlockingOperation else { return }
        activeDraft = nil
        activeDraftBaseline = nil
        failure = nil
        publishIntegrationState()
    }

    func discardActiveDraftIfClean(id: String) {
        guard activeDraft?.id == id, !hasUnsavedChanges else { return }
        discardActiveDraft()
    }

    func clearFailure() {
        failure = nil
    }

    @discardableResult
    func saveActiveDraft() async -> Bool {
        guard let activeDraft else {
            return reject(.actionNotFound)
        }
        guard activeDraft.validation == .valid else {
            return reject(.invalidDraft(activeDraft.validation))
        }
        guard hasUnsavedChanges else { return true }
        guard let catalog else {
            return reject(.catalogNotLoaded)
        }

        do {
            let action = try activeDraft.action()
            let candidate = try activeDraftBaseline == nil
                ? catalog.addingCustomAction(action)
                : catalog.replacingCustomAction(action)
            guard await persist(candidate) else { return false }
            self.activeDraft = nil
            activeDraftBaseline = nil
            publishIntegrationState()
            return true
        } catch {
            return reject(.catalogRejectedChange)
        }
    }

    @discardableResult
    func setCustomActionEnabled(
        id: String,
        isEnabled: Bool
    ) async -> Bool {
        await mutateCatalog { catalog in
            try catalog.settingCustomActionEnabled(
                id: id,
                isEnabled: isEnabled
            )
        }
    }

    @discardableResult
    func deleteCustomAction(id: String) async -> Bool {
        guard let catalog else {
            return reject(.catalogNotLoaded)
        }
        guard !isBlockingOperation else {
            return reject(.operationInFlight)
        }
        do {
            let candidate = try catalog.deletingCustomAction(id: id)
            guard await persist(candidate) else { return false }
            if activeDraft?.id == id {
                activeDraft = nil
                activeDraftBaseline = nil
                publishIntegrationState()
            }
            return true
        } catch TextFixCatalog.MutationError.builtInActionCannotBeModified {
            return reject(.builtInReadOnly)
        } catch {
            return reject(.catalogRejectedChange)
        }
    }

    @discardableResult
    func moveCustomActions(
        fromOffsets sourceOffsets: IndexSet,
        toOffset destinationOffset: Int
    ) async -> Bool {
        guard let catalog else {
            return reject(.catalogNotLoaded)
        }
        guard activeDraft == nil else {
            return reject(.anotherDraftIsOpen)
        }
        let customActions = catalog.customActions
        let indexes = sourceOffsets.sorted()
        guard !indexes.isEmpty,
              indexes.allSatisfy(customActions.indices.contains),
              (0...customActions.count).contains(destinationOffset)
        else {
            return reject(.invalidMove)
        }

        let movingActions = indexes.map { customActions[$0] }
        var remainingActions = customActions.enumerated().compactMap {
            indexes.contains($0.offset) ? nil : $0.element
        }
        let removedBeforeDestination = indexes.filter {
            $0 < destinationOffset
        }.count
        let insertionIndex = destinationOffset - removedBeforeDestination
        guard (0...remainingActions.count).contains(insertionIndex) else {
            return reject(.invalidMove)
        }
        remainingActions.insert(
            contentsOf: movingActions,
            at: insertionIndex
        )
        guard remainingActions != customActions else { return true }

        do {
            let candidate = try TextFixCatalog(
                actions: Array(catalog.actions.prefix(2)) + remainingActions
            )
            return await persist(candidate)
        } catch {
            return reject(.catalogRejectedChange)
        }
    }

    @discardableResult
    func restoreDefaults() async -> Bool {
        await mutateCatalog { try $0.restoringDefaults() }
    }

    private func mutateCatalog(
        _ mutation: (TextFixCatalog) throws -> TextFixCatalog
    ) async -> Bool {
        guard let catalog else {
            return reject(.catalogNotLoaded)
        }
        guard !isBlockingOperation else {
            return reject(.operationInFlight)
        }
        guard activeDraft == nil else {
            return reject(.anotherDraftIsOpen)
        }
        do {
            let candidate = try mutation(catalog)
            guard candidate != catalog else { return true }
            return await persist(candidate)
        } catch TextFixCatalog.MutationError.builtInActionCannotBeModified {
            return reject(.builtInReadOnly)
        } catch {
            return reject(.catalogRejectedChange)
        }
    }

    private func persist(_ candidate: TextFixCatalog) async -> Bool {
        phase = .saving
        failure = nil
        publishIntegrationState()
        do {
            let savedCatalog = try await client.save(candidate)
            guard !Task.isCancelled else {
                phase = .ready
                publishIntegrationState()
                return false
            }
            catalog = savedCatalog
            phase = .ready
            publishIntegrationState()
            return true
        } catch is CancellationError {
            phase = .ready
            publishIntegrationState()
            return false
        } catch {
            phase = .ready
            failure = .saveFailed
            publishIntegrationState()
            return false
        }
    }

    @discardableResult
    private func reject(
        _ error: IOSTextFixEditorMutationError
    ) -> Bool {
        failure = .changeRejected(error)
        return false
    }

    private func clearChangeFailure() {
        guard case .changeRejected = failure else { return }
        failure = nil
    }

    private func publishIntegrationState() {
        let unsavedState = hasUnsavedChanges
        if unsavedState != lastReportedUnsavedState {
            lastReportedUnsavedState = unsavedState
            onUnsavedStateChange(unsavedState)
        }

        let blockingState = isBlockingOperation
        if blockingState != lastReportedBlockingState {
            lastReportedBlockingState = blockingState
            onBlockingStateChange(blockingState)
        }
    }
}
