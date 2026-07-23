import Combine
import Foundation
import HoldTypeDomain

enum FixesPaletteSelectionMovement {
    case up
    case down
}

@MainActor
final class FixesPaletteModel: ObservableObject {
    typealias ActionHandler = @MainActor (String) -> Void
    typealias DismissHandler = @MainActor () -> Void

    @Published private(set) var actions: [FixesPaletteActionPresentation]
    @Published private(set) var searchText = ""
    @Published private(set) var selectedActionID: String?
    @Published private(set) var status: FixesPaletteStatus

    private let onActivate: ActionHandler
    private let onDismiss: DismissHandler
    private var didRequestDismissal = false

    init(
        catalog: TextFixCatalog,
        status: FixesPaletteStatus = .ready,
        onActivate: @escaping ActionHandler,
        onDismiss: @escaping DismissHandler
    ) {
        let actions = catalog.enabledActions.map(FixesPaletteActionPresentation.init)
        self.actions = actions
        self.status = status
        self.onActivate = onActivate
        self.onDismiss = onDismiss
        selectedActionID = actions.first?.id
    }

    var visibleActions: [FixesPaletteActionPresentation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return actions
        }

        return actions.filter { action in
            action.title.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }

    var selectedAction: FixesPaletteActionPresentation? {
        guard let selectedActionID else {
            return nil
        }

        return visibleActions.first { $0.id == selectedActionID }
    }

    var statusPresentation: FixesPaletteStatusPresentation? {
        let processingTitle: String?
        if case .processing(let actionID) = status {
            processingTitle = actions.first { $0.id == actionID }?.title
        } else {
            processingTitle = nil
        }

        return status.presentation(actionTitle: processingTitle)
    }

    var canActivateSelection: Bool {
        !didRequestDismissal
            && status.allowsActionActivation
            && selectedAction != nil
    }

    func setSearchText(_ searchText: String) {
        guard !didRequestDismissal else {
            return
        }

        self.searchText = searchText
        reconcileSelection()
    }

    func updateActions(from catalog: TextFixCatalog) {
        actions = catalog.enabledActions.map(FixesPaletteActionPresentation.init)
        reconcileSelection()
    }

    func updateStatus(_ status: FixesPaletteStatus) {
        guard !didRequestDismissal else {
            return
        }

        self.status = status
    }

    func moveSelection(_ movement: FixesPaletteSelectionMovement) {
        guard !didRequestDismissal,
              !visibleActions.isEmpty
        else {
            return
        }

        let currentIndex = selectedActionID.flatMap { selectedActionID in
            visibleActions.firstIndex { $0.id == selectedActionID }
        }
        let nextIndex: Int
        switch movement {
        case .up:
            nextIndex = max((currentIndex ?? 0) - 1, 0)
        case .down:
            nextIndex = min((currentIndex ?? -1) + 1, visibleActions.count - 1)
        }
        selectedActionID = visibleActions[nextIndex].id
    }

    func selectAction(id: String) {
        guard !didRequestDismissal,
              visibleActions.contains(where: { $0.id == id })
        else {
            return
        }

        selectedActionID = id
    }

    func activateSelection() {
        guard canActivateSelection,
              let selectedAction
        else {
            return
        }

        status = .processing(actionID: selectedAction.id)
        onActivate(selectedAction.id)
    }

    func requestDismissal() {
        guard !didRequestDismissal else {
            return
        }

        didRequestDismissal = true
        onDismiss()
    }

    private func reconcileSelection() {
        let visibleActions = visibleActions
        guard !visibleActions.isEmpty else {
            selectedActionID = nil
            return
        }
        guard let selectedActionID,
              visibleActions.contains(where: { $0.id == selectedActionID })
        else {
            self.selectedActionID = visibleActions.first?.id
            return
        }
    }
}
