import HoldTypeDomain
@testable import HoldTypeIOS

enum IOSTextFixEditorTestError: Error {
    case unavailable
}
actor IOSTextFixEditorTestStore {
    private var catalog: TextFixCatalog
    private var loadShouldFail = false
    private var saveShouldFail = false
    private var savedCatalogs: [TextFixCatalog] = []

    init(catalog: TextFixCatalog = .defaults) {
        self.catalog = catalog
    }

    nonisolated func client() -> IOSTextFixEditorClient {
        IOSTextFixEditorClient(
            load: { try await self.load() },
            save: { try await self.save($0) }
        )
    }

    func setLoadShouldFail(_ shouldFail: Bool) {
        loadShouldFail = shouldFail
    }

    func setSaveShouldFail(_ shouldFail: Bool) {
        saveShouldFail = shouldFail
    }

    func saveCount() -> Int {
        savedCatalogs.count
    }

    func latestSavedCatalog() -> TextFixCatalog? {
        savedCatalogs.last
    }

    private func load() throws -> TextFixCatalog {
        guard !loadShouldFail else {
            throw IOSTextFixEditorTestError.unavailable
        }
        return catalog
    }

    private func save(
        _ candidate: TextFixCatalog
    ) throws -> TextFixCatalog {
        guard !saveShouldFail else {
            throw IOSTextFixEditorTestError.unavailable
        }
        catalog = candidate
        savedCatalogs.append(candidate)
        return candidate
    }
}

@MainActor
final class IOSTextFixEditorCallbackRecorder {
    private(set) var unsavedStates: [Bool] = []
    private(set) var blockingStates: [Bool] = []

    func recordUnsaved(_ value: Bool) {
        unsavedStates.append(value)
    }

    func recordBlocking(_ value: Bool) {
        blockingStates.append(value)
    }
}
